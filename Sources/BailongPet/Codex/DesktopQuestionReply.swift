import Foundation
import Darwin

// 当前桌面端的本机、版本化 IPC。只提交用户点击确认的问卷答案；不操作数据库。
// 协议来源：已安装桌面端的 thread-owner-discovery / thread-follower-steer-turn v1。
enum DesktopQuestionReply {
    static func submit(thread:String,cwd:String,questions:[TaskQuestion],answers:[String:String],completion:@escaping (Error?) -> Void) {
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let replies = questions.filter {!(answers[$0.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.map {["questionItemId":$0.id,"question":$0.prompt,"answer":answers[$0.id] ?? ""]}
                guard !replies.isEmpty else {throw PetFailure(message:"请填写回答后再提交。")}
                let json = try JSONSerialization.data(withJSONObject:replies)
                let text = "<send_user_message_question_reply>\n"+String(decoding:json,as:UTF8.self)+"\n</send_user_message_question_reply>"
                let connection = try DesktopSocket()
                let initial = try connection.call("initialize",params:["clientType":"bailong-pet"],version:0)
                guard let client = (initial["result"] as? [String:Any])?["clientId"] as? String else {throw PetFailure(message:"Codex 未返回本机连接标识。")}
                connection.clientID = client
                let owner = try connection.call("thread-owner-discovery",params:["hostId":"local","conversationId":thread],version:1)
                guard let target = owner["handledByClientId"] as? String else {throw PetFailure(message:"未找到原会话窗口，请转到 Codex 回答。")}
                let input:[[String:Any]] = [["type":"text","text":text,"text_elements":[]]]
                _ = try connection.call("thread-follower-steer-turn",params:["conversationId":thread,"input":input,
                    "clientUserMessageId":UUID().uuidString,"attachments":[],
                    "restoreMessage":["text":text,"cwd":cwd,"context":["workspaceRoots":[cwd]]]],version:1,target:target)
                DispatchQueue.main.async {completion(nil)}
            } catch {DispatchQueue.main.async {completion(error)}}
        }
    }
}

final class DesktopSocket {
    struct Unavailable:LocalizedError {
        var errorDescription:String? {"Codex 本机通信尚未就绪。"}
    }
    struct Disconnected:LocalizedError {
        var errorDescription:String? {"Codex 本机连接已断开。"}
    }
    struct ResponseTimeout:LocalizedError {
        var method:String? = nil
        var errorDescription:String? {method.map {"Codex 请求超时（\($0)）。"} ?? "等待 Codex 响应超时。"}
    }
    struct RequestFailure:LocalizedError {
        let method:String, code:String
        var errorDescription:String? {"Codex 请求失败（\(method)）：\(code)"}
    }
    struct WakeupInterrupt:Error {}
    private let fd:Int32
    private let timeoutSeconds:Int
    var clientID = "initializing-client"
    init(timeoutSeconds:Int = 8) throws {
        self.timeoutSeconds = timeoutSeconds
        let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
        let path = root+"/ipc/ipc.sock"
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue:address.sun_path) else {throw PetFailure(message:"Codex 本机通信路径过长。")}
        var info = stat()
        if lstat(path,&info) != 0 {
            if errno == ENOENT {throw Unavailable()}
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))
        }
        guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else {throw PetFailure(message:"Codex 本机通信路径不是当前用户的套接字。")}
        fd = socket(AF_UNIX,SOCK_STREAM,0)
        guard fd >= 0 else {throw PetFailure(message:"无法创建本机通信连接。")}
        var timeout = timeval(tv_sec:timeoutSeconds,tv_usec:0), noSignal:Int32 = 1
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
        setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
        setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout.size(ofValue:noSignal)))
        withUnsafeMutableBytes(of:&address.sun_path) {$0.copyBytes(from:bytes.map {UInt8(bitPattern:$0)})}
        let connected = withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        if connected != 0 {
            let code = errno; close(fd)
            if code == ENOENT || code == ECONNREFUSED {throw Unavailable()}
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))
        }
    }
    deinit {close(fd)}
    func call(_ method:String,params:[String:Any],version:Int,target:String? = nil,deadline operationDeadline:Date? = nil,wakeup:(([String:Any]) -> Bool)? = nil) throws -> [String:Any] {
        let deadline = min(operationDeadline ?? .distantFuture,Date().addingTimeInterval(Double(timeoutSeconds)))
        let id = UUID().uuidString
        // 主动写入才逐次记录。后台发现 owner、刷新设置和订阅心跳沿用原节奏。
        let monitor = Self.monitoredMethods.contains(method) ? TerminalMonitor.active : nil
        let start = monitor.map { _ in ProcessInfo.processInfo.systemUptime }
        func record(_ event:String,_ detail:String = "",_ level:TerminalMonitor.Level = .info) {
            guard let monitor,let start else {return}
            let rpc = method+" v\(version)  ·  RPC#"+TerminalMonitor.tag(id)
            let thread = (params["conversationId"] as? String).map {"  会话#"+TerminalMonitor.tag($0)} ?? ""
            let elapsed = TerminalMonitor.milliseconds(ProcessInfo.processInfo.systemUptime-start)
            monitor.write(.ipc,event+"  "+rpc+thread+"  ·  "+elapsed+detail,level)
        }
        do {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {throw ResponseTimeout(method:method)}
            let timeoutMs = max(500,min(max(1000,(timeoutSeconds-1)*1000),Int(ceil(remaining*1000))))
            var request:[String:Any] = ["type":"request","requestId":id,"sourceClientId":clientID,"version":version,"method":method,"params":params,"timeoutMs":timeoutMs]
            if let target {request["targetClientId"] = target}
            try send(request)
            record("→ 请求")
            let response = try receiveResponse(id:id,method:method,deadline:deadline,wakeup:wakeup)
            record("← 回执","",.success)
            return response
        } catch {
            if monitor != nil {
                let reason:String
                switch error {
                case is ResponseTimeout:reason = "等待响应超时"
                case is Disconnected:reason = "桌面端已断开"
                case is RequestFailure:reason = "桌面端返回错误"
                default:reason = TerminalMonitor.errorCode(error)
                }
                record("× 失败","  ·  "+reason,.error)
            }
            throw error
        }
    }
    private static let monitoredMethods:Set<String> = ["thread-follower-start-turn","thread-follower-steer-turn",
        "thread-follower-command-approval-decision","thread-follower-file-approval-decision","thread-follower-permissions-request-approval-response"]
    private func receiveResponse(id:String,method:String,deadline:Date,wakeup:(([String:Any]) -> Bool)?) throws -> [String:Any] {
        while Date() < deadline {
            let value:[String:Any]
            do {value = try receive(deadline:deadline)}
            catch is ResponseTimeout {throw ResponseTimeout(method:method)}
            catch is Disconnected {throw Disconnected()}
            catch {throw PetFailure(message:"Codex 本机请求失败（\(method)）："+error.localizedDescription)}
            if try handleControlFrame(value) {continue}
            if value["type"] as? String == "broadcast",wakeup?(value) == true {throw WakeupInterrupt()}
            guard value["type"] as? String == "response",value["requestId"] as? String == id else {continue}
            guard value["resultType"] as? String == "success" else {throw RequestFailure(method:method,code:value["error"] as? String ?? "请求失败")}
            return value
        }
        throw ResponseTimeout(method:method)
    }
    func broadcast(_ method:String,params:[String:Any],version:Int) throws {
        try send(["type":"broadcast","method":method,"sourceClientId":clientID,"params":params,"version":version])
    }
    func receiveIfAvailable(milliseconds:Int32) throws -> [String:Any]? {
        let deadline = Date().addingTimeInterval(Double(milliseconds)/1000)
        repeat {
            var descriptor = pollfd(fd:fd,events:Int16(POLLIN),revents:0)
            let remaining = Int32(max(0,deadline.timeIntervalSinceNow*1000))
            let result = Darwin.poll(&descriptor,1,remaining)
            guard result >= 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
            if result == 0 {return nil}
            let value = try receive(deadline:Date().addingTimeInterval(Double(timeoutSeconds)))
            if try !handleControlFrame(value) {return value}
        } while Date() < deadline
        return nil
    }
    // 桌宠只发起请求和订阅广播，不承接其他客户端的会话请求。
    private func handleControlFrame(_ value:[String:Any]) throws -> Bool {
        guard let id = value["requestId"] as? String else {return false}
        switch value["type"] as? String {
        case "client-discovery-request":
            try send(["type":"client-discovery-response","requestId":id,"response":["canHandle":false]])
            return true
        case "request":
            try send(["type":"response","requestId":id,"resultType":"error","error":"no-handler-for-request"])
            return true
        default:return false
        }
    }
    private func send(_ value:[String:Any]) throws {
        let json = try JSONSerialization.data(withJSONObject:value)
        var length = UInt32(json.count).littleEndian
        var frame = withUnsafeBytes(of:&length) {Data($0)}; frame.append(json)
        try frame.withUnsafeBytes {bytes in
            var offset = 0
            while offset < bytes.count {
                let sent = Darwin.send(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset,0)
                if sent < 0 && (errno == EPIPE || errno == ECONNRESET) {throw Disconnected()}
                guard sent > 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}; offset += sent
            }
        }
    }
    private func receive(deadline:Date) throws -> [String:Any] {
        let header = try read(4,deadline:deadline), size = header.enumerated().reduce(UInt32(0)) {$0 | UInt32($1.element) << (8*$1.offset)}
        guard size > 0 && size <= 16*1024*1024 else {throw PetFailure(message:"Codex 本机消息格式不兼容。")}
        guard let value = try JSONSerialization.jsonObject(with:read(Int(size),deadline:deadline)) as? [String:Any] else {throw PetFailure(message:"Codex 本机消息格式不兼容。")}
        return value
    }
    private func read(_ count:Int,deadline:Date) throws -> Data {
        var result = Data(count:count)
        try result.withUnsafeMutableBytes {bytes in
            var offset = 0
            while offset < count {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else {throw ResponseTimeout()}
                // poll 同时报告数据与连接关闭，避免对已被对端关闭的 socket 设置超时。
                var descriptor = pollfd(fd:fd,events:Int16(POLLIN),revents:0)
                let ready = Darwin.poll(&descriptor,1,Int32(max(1,ceil(remaining*1000))))
                if ready < 0 && errno == EINTR {continue}
                guard ready >= 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
                guard ready > 0 else {throw ResponseTimeout()}
                let got = recv(fd,bytes.baseAddress!.advanced(by:offset),count-offset,0)
                if got < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {throw ResponseTimeout()}
                if got == 0 || (got < 0 && errno == ECONNRESET) {throw Disconnected()}
                guard got > 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
                offset += got
            }
        }
        return result
    }
}
