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
        guard lstat(path,&info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else {throw PetFailure(message:"Codex 本机通信尚未就绪，请打开 Codex 后重试。")}
        fd = socket(AF_UNIX,SOCK_STREAM,0)
        guard fd >= 0 else {throw PetFailure(message:"无法创建本机通信连接。")}
        var timeout = timeval(tv_sec:timeoutSeconds,tv_usec:0), noSignal:Int32 = 1
        setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
        setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)))
        setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout.size(ofValue:noSignal)))
        withUnsafeMutableBytes(of:&address.sun_path) {$0.copyBytes(from:bytes.map {UInt8(bitPattern:$0)})}
        let connected = withUnsafePointer(to:&address) {$0.withMemoryRebound(to:sockaddr.self,capacity:1) {Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}}
        if connected != 0 {let code = errno; close(fd); throw NSError(domain:NSPOSIXErrorDomain,code:Int(code))}
    }
    deinit {close(fd)}
    func call(_ method:String,params:[String:Any],version:Int,target:String? = nil) throws -> [String:Any] {
        let id = UUID().uuidString
        var request:[String:Any] = ["type":"request","requestId":id,"sourceClientId":clientID,"version":version,"method":method,"params":params,"timeoutMs":(timeoutSeconds-1)*1000]
        if let target {request["targetClientId"] = target}
        let json = try JSONSerialization.data(withJSONObject:request)
        var length = UInt32(json.count).littleEndian
        var frame = withUnsafeBytes(of:&length) {Data($0)}; frame.append(json)
        try frame.withUnsafeBytes {bytes in
            var offset = 0
            while offset < bytes.count {
                let sent = Darwin.send(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset,0)
                guard sent > 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}; offset += sent
            }
        }
        let deadline = Date().addingTimeInterval(Double(timeoutSeconds))
        while Date() < deadline {
            let header = try read(4), size = header.enumerated().reduce(UInt32(0)) {$0 | UInt32($1.element) << (8*$1.offset)}
            guard size > 0 && size <= 16*1024*1024 else {throw PetFailure(message:"Codex 本机消息格式不兼容。")}
            guard let value = try JSONSerialization.jsonObject(with:read(Int(size))) as? [String:Any] else {throw PetFailure(message:"Codex 本机消息格式不兼容。")}
            guard value["requestId"] as? String == id else {continue}
            guard value["resultType"] as? String == "success" else {throw PetFailure(message:"Codex 未接受回答："+(value["error"] as? String ?? "请求失败"))}
            return value
        }
        throw PetFailure(message:"Codex 未在规定时间内确认回答。请转到 Codex 检查提交结果。")
    }
    private func read(_ count:Int) throws -> Data {
        var result = Data(count:count)
        try result.withUnsafeMutableBytes {bytes in
            var offset = 0
            while offset < count {
                let got = recv(fd,bytes.baseAddress!.advanced(by:offset),count-offset,0)
                guard got > 0 else {throw PetFailure(message:got == 0 ? "Codex 本机连接已关闭。" : "Codex 本机通信失败："+String(cString:strerror(errno)))}
                offset += got
            }
        }
        return result
    }
}
