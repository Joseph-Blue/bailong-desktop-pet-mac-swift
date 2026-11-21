import Foundation
import Darwin

// Codex 启动同一个桌宠可执行文件处理 stdin。一条连接只对应一个等待用户处理的请求。
enum DesktopPermissionHook {
    static let inputLimit = 64 * 1024
    static var socketPath:String {
        var directory = [CChar](repeating:0,count:Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR,&directory,directory.count) > 0 else {return ""}
        return URL(fileURLWithPath:String(cString:directory)).appendingPathComponent("bailong-permission.sock").path
    }
    enum Decision:UInt8 {case allow = 65, deny = 68}
    struct Request:Codable {
        let thread:String, turn:String, cwd:String, command:String
        let reason:String?

        init?(_ data:Data) {
            guard data.count <= DesktopPermissionHook.inputLimit,
                  let event = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                  event["hook_event_name"] as? String == "PermissionRequest",event["tool_name"] as? String == "Bash",
                  let thread = event["session_id"] as? String,UUID(uuidString:thread) != nil,
                  let turn = event["turn_id"] as? String,UUID(uuidString:turn) != nil,
                  let cwd = event["cwd"] as? String,cwd.hasPrefix("/"),
                  let input = event["tool_input"] as? [String:Any],Set(input.keys).isSubset(of:["command","description"]),
                  let command = input["command"] as? String,!command.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  input["description"] == nil || input["description"] is NSNull || input["description"] is String else {return nil}
            self.thread = thread; self.turn = turn; self.cwd = cwd; self.command = command
            reason = input["description"] as? String
        }
    }

    static func address(_ path:String,_ body:(UnsafePointer<sockaddr>,socklen_t)->Int32) -> Int32 {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard !path.isEmpty,bytes.count <= MemoryLayout.size(ofValue:address.sun_path) else {errno = ENAMETOOLONG; return -1}
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of:&address.sun_path) {$0.copyBytes(from:bytes.map {UInt8(bitPattern:$0)})}
        return withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {body($0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
    }
    static func configure(_ fd:Int32) -> Bool {
        var on:Int32 = 1
        return fcntl(fd,F_SETFD,FD_CLOEXEC) == 0 && setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&on,socklen_t(MemoryLayout.size(ofValue:on))) == 0
    }
    static func isPetPeer(_ fd:Int32) -> Bool {
        var uid:uid_t = 0, gid:gid_t = 0, pid:pid_t = 0
        var length = socklen_t(MemoryLayout.size(ofValue:pid))
        guard getpeereid(fd,&uid,&gid) == 0,uid == geteuid(),
              getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&length) == 0,pid > 0 else {return false}
        func executable(_ pid:pid_t) -> String? {
            var path = [CChar](repeating:0,count:4 * Int(MAXPATHLEN))
            guard path.withUnsafeMutableBytes({proc_pidpath(pid,$0.baseAddress,UInt32($0.count))}) > 0 else {return nil}
            return String(cString:path)
        }
        guard let own = executable(getpid()) else {return false}
        return executable(pid) == own
    }

    static func run(path:String = socketPath) throws {
        var input = Data()
        while input.count <= inputLimit {
            guard let chunk = try FileHandle.standardInput.read(upToCount:inputLimit+1-input.count),!chunk.isEmpty else {break}
            input.append(chunk)
        }
        guard let request = Request(input) else {return}
        let fd = socket(AF_UNIX,SOCK_STREAM,0)
        guard fd >= 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        defer {Darwin.close(fd)}
        guard configure(fd),address(path,{Darwin.connect(fd,$0,$1)}) == 0,isPetPeer(fd) else {return}
        var timeout = timeval(tv_sec:115,tv_usec:0)
        guard setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout))) == 0,
              setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout))) == 0 else {return}
        let frame = try JSONEncoder().encode(request) + Data([10])
        guard frame.count <= inputLimit else {return}
        let sent = frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.send(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset,0)
                if count < 0 && errno == EINTR {continue}
                guard count > 0 else {return false}
                offset += count
            }
            return true
        }
        guard sent else {return}
        var byte:UInt8 = 0
        guard recv(fd,&byte,1,0) == 1,let decision = Decision(rawValue:byte) else {return}
        let output = ["hookSpecificOutput":["hookEventName":"PermissionRequest","decision":["behavior":decision == .allow ? "allow" : "deny"]]] as [String:Any]
        try FileHandle.standardOutput.write(contentsOf:JSONSerialization.data(withJSONObject:output))
    }
}

// Listener、连接和待审批表都归主队列；收包用非阻塞 fd，等待点击不占用线程。
final class DesktopPermissionListener {
    typealias Hook = DesktopPermissionHook
    private final class Client {
        let id = UUID(), source:DispatchSourceRead
        let arrival = ProcessInfo.processInfo.systemUptime
        var buffer = Data(), request:Hook.Request?, presented = false
        init(_ source:DispatchSourceRead) {self.source = source}
    }
    private let path:String
    private var listener:DispatchSourceRead?
    private var clients = [UUID:Client]()
    var canPresent:()->Bool = {false}
    init(path:String = Hook.socketPath) {self.path = path}

    // 调用方已持有桌宠单实例锁，因此只需清除上次异常退出时遗留的本用户 socket。
    func start() throws {
        let fd = socket(AF_UNIX,SOCK_STREAM,0)
        guard fd >= 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        var bound = false
        defer {if listener == nil {Darwin.close(fd); if bound {unlink(path)}}}
        if !path.isEmpty {
            var st = stat()
            if lstat(path,&st) == 0 {
                guard st.st_uid == geteuid(),st.st_mode & S_IFMT == S_IFSOCK,unlink(path) == 0 else {throw POSIXError(.EEXIST)}
            }
        }
        guard Hook.configure(fd),fcntl(fd,F_SETFL,O_NONBLOCK) == 0,
              Hook.address(path,{Darwin.bind(fd,$0,$1)}) == 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        bound = true
        guard chmod(path,0o600) == 0,listen(fd,8) == 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        let source = DispatchSource.makeReadSource(fileDescriptor:fd,queue:.main)
        source.setEventHandler { [weak self] in self?.accept(fd) }
        source.setCancelHandler {Darwin.close(fd)}
        listener = source; source.resume()
    }

    private func accept(_ listenerFD:Int32) {
        let fd = Darwin.accept(listenerFD,nil,nil)
        guard fd >= 0 else {return}
        guard canPresent(),clients.count < 16,Hook.configure(fd),fcntl(fd,F_SETFL,O_NONBLOCK) == 0,Hook.isPetPeer(fd) else {Darwin.close(fd); return}
        let source = DispatchSource.makeReadSource(fileDescriptor:fd,queue:.main)
        let client = Client(source)
        clients[client.id] = client
        source.setEventHandler { [weak self,weak client] in
            guard let self,let client else {return}
            var bytes = [UInt8](repeating:0,count:4096)
            let count = recv(fd,&bytes,bytes.count,0)
            if count < 0 && (errno == EAGAIN || errno == EINTR) {return}
            guard count > 0,client.request == nil,client.buffer.count + count <= Hook.inputLimit else {self.remove(client); return}
            client.buffer.append(contentsOf:bytes.prefix(count))
            guard client.buffer.contains(10) else {return}
            guard client.buffer.last == 10,let request = try? JSONDecoder().decode(Hook.Request.self,from:client.buffer) else {self.remove(client); return}
            client.request = request; client.buffer = Data()
        }
        source.setCancelHandler {Darwin.close(fd)}
        source.resume()
        // 用户切换到原窗口、客户端退出和未出现匹配轮次都交回 Codex 自己审批。
        DispatchQueue.main.asyncAfter(deadline:.now()+5) { [weak self,weak client] in
            if let client,!client.presented {self?.remove(client)}
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+110) { [weak self,weak client] in
            if let client {self?.remove(client)}
        }
    }

    func project(into values:inout [PublicSnapshot]) {
        guard canPresent() else {discard(); return}
        for client in clients.values.sorted(by:{$0.arrival < $1.arrival}) {
            guard let request = client.request else {continue}
            guard let i = values.firstIndex(where:{$0.isLatest && ($0.logical == request.thread || $0.actual == request.thread) && $0.turn == request.turn && activeStatuses.contains($0.status)}) else {
                if client.presented {remove(client)}
                continue
            }
            client.presented = true
            guard values[i].approval == nil else {continue}
            let approval = DesktopApproval(hook:request,id:client.id) { [weak self,weak client] decision in
                guard let self,let client,self.clients[client.id] === client,self.canPresent() else {return false}
                defer {self.remove(client)}
                guard let decision else {return true}
                var byte = decision.rawValue
                return Darwin.send(Int32(client.source.handle),&byte,1,0) == 1
            }
            values[i].approval = approval; values[i].approvalID = approval.identity
            values[i].attention = approval.attention; values[i].status = "waitingForApproval"; values[i].alert = approval.attention.body
        }
    }

    private func remove(_ client:Client) {
        if clients.removeValue(forKey:client.id) != nil {client.source.cancel()}
    }
    func discard() {for client in Array(clients.values) {remove(client)}}
    func stop() {
        discard()
        if let listener {unlink(path); listener.cancel(); self.listener = nil}
    }
}
