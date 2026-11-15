import Foundation

// 普通回复由桌面端原会话处理；不复用桌宠内置任务的人格、模型及权限参数。
enum DesktopReply {
    enum Mode {case start, steer}
    static func mode(for status:String) -> Mode? {
        if ["inProgress","running"].contains(status) {return .steer}
        if ["completed","failed","interrupted","cancelled","canceled"].contains(status) {return .start}
        return nil
    }
    struct OwnerUnavailable:LocalizedError {
        var errorDescription:String? {"Codex 尚未加载这条会话。"}
    }
    private static func initialize(timeout:Int,deadline:Date?) throws -> DesktopSocket {
        let connection = try DesktopSocket(timeoutSeconds:timeout)
        let initialized = try connection.call("initialize",params:["clientType":"bailong-pet"],version:0,deadline:deadline)
        guard let client = (initialized["result"] as? [String:Any])?["clientId"] as? String else {throw PetFailure(message:"Codex 未返回本机连接标识。")}
        connection.clientID = client
        return connection
    }
    private static func connect(thread:String,timeout:Int = 8,deadline:Date? = nil) throws -> (DesktopSocket,String) {
        let connection = try initialize(timeout:timeout,deadline:deadline)
        let owner:[String:Any]
        do {owner = try connection.call("thread-owner-discovery",params:["hostId":"local","conversationId":thread],version:1,deadline:deadline)}
        catch let error as DesktopSocket.RequestFailure where error.code == "no-client-found" {throw OwnerUnavailable()}
        guard let target = owner["handledByClientId"] as? String else {throw OwnerUnavailable()}
        return (connection,target)
    }
    static func connectionPending(_ error:Error) -> Bool {
        if let failure = error as? DesktopSocket.RequestFailure {
            return ["no-client-found","client-disconnected","request-timeout","server-closed"].contains(failure.code)
        }
        return error is OwnerUnavailable || error is DesktopSocket.ResponseTimeout || error is DesktopSocket.Unavailable || error is DesktopSocket.Disconnected
    }
    struct Settings {
        let model:String
        let effort:String?
        let effortFromHistory:Bool
    }
    struct PreparedConnection {
        let settings:Settings
        fileprivate let thread:String
        fileprivate let socket:DesktopSocket
        fileprivate let owner:String
    }
    static func prepareConnection(thread:String,timeout:Int = 12,completion:@escaping (Result<PreparedConnection,Error>) -> Void) {
        DispatchQueue.global(qos:.utility).async {
            let result = Result<PreparedConnection,Error> {
                let deadline = Date().addingTimeInterval(Double(timeout))
                // 本机路由发现阶段最多等待 10 秒，须先收到 no-client-found 再分类。
                let (connection,target) = try connect(thread:thread,timeout:30,deadline:deadline)
                let response = try connection.call("thread-follower-read-model-settings",params:["conversationId":thread],version:1,target:target,deadline:deadline)
                guard let result = response["result"] as? [String:Any],let settings = result["settings"] as? [String:Any],
                      let model = settings["model"] as? String,!model.isEmpty else {throw PetFailure(message:"Codex 未提供当前会话的模型设置。")}
                let liveEffort = settings["reasoningEffort"] as? String
                let recordedEffort = liveEffort == nil ? try DesktopHistoryReader.recordedReasoningEffort(thread:thread,model:model) : nil
                return PreparedConnection(settings:Settings(model:model,effort:liveEffort ?? recordedEffort,effortFromHistory:recordedEffort != nil),thread:thread,socket:connection,owner:target)
            }
            DispatchQueue.main.async {completion(result)}
        }
    }
    struct Receipt {
        let turnID:String
        let status:String
    }
    // 仅在提交消息之前返回；调用方可继续连接，不会重复发送用户输入。
    struct ConnectionPending:LocalizedError {
        let underlying:Error
        var errorDescription:String? {underlying.localizedDescription}
    }
    struct Unconfirmed: LocalizedError {
        let underlying:Error
        var errorDescription:String? {"尚未收到发送确认。请先到 Codex 查看消息是否已发送，确认未发送后再重试。\n\n"+underlying.localizedDescription}
    }
    static func submit(thread:String,previousTurn:String,cwd:String,text:String,mode:Mode,connectionDeadline:Date,prepared:PreparedConnection? = nil,onConnected:@escaping () -> Void,completion:@escaping (Result<Receipt,Error>) -> Void) {
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result<Receipt,Error> {
                let connection:DesktopSocket, target:String
                do {
                    // 路由发现只看发起时的客户端；短请求让新打开的会话及时参与下一次发现。
                    if let prepared {
                        guard prepared.thread == thread else {throw PetFailure(message:"准备连接与发送会话不一致。")}
                        (connection,target) = (prepared.socket,prepared.owner)
                    }
                    else {(connection,target) = try connect(thread:thread,timeout:30,deadline:min(connectionDeadline,Date().addingTimeInterval(2)))}
                } catch where connectionPending(error) {
                    throw ConnectionPending(underlying:error)
                }
                // 紧接发送前重新检查数据库，仅投影身份与状态，不读取对话或凭证。
                try DesktopHistoryReader.requireReplyConversation(thread,previousTurn:previousTurn,steering:mode == .steer)
                DispatchQueue.main.async {onConnected()}
                let messageID = UUID().uuidString
                let request:[String:Any] = ["threadId":thread,"clientUserMessageId":messageID,
                    "input":[["type":"text","text":text,"text_elements":[]]]]
                let context:[String:Any] = ["inheritThreadSettings":true,"useUserMessageAdmission":false,"useAppServerPermissionDefault":false,"attachments":[]]
                do {
                    if mode == .steer {
                        let response = try connection.call("thread-follower-steer-turn",params:["conversationId":thread,
                            "input":request["input"]!,"clientUserMessageId":messageID,"attachments":[],
                            "restoreMessage":["text":text,"cwd":cwd,"context":["workspaceRoots":[cwd]]]],version:1,target:target)
                        guard let envelope = response["result"] as? [String:Any],let result = envelope["result"] as? [String:Any],
                              let id = result["turnId"] as? String,id == previousTurn else {throw PetFailure(message:"Codex 未确认插话进入原轮次。")}
                        return Receipt(turnID:id,status:"inProgress")
                    }
                    // 本机 26.1027.30824：start-turn v2；问卷 steer-turn 仍使用 v1。
                    let response = try connection.call("thread-follower-start-turn",params:["conversationId":thread,
                        "turnStart":["request":request,"context":context]],version:2,target:target)
                    guard let envelope = response["result"] as? [String:Any],
                          let result = envelope["result"] as? [String:Any],
                          let turn = result["turn"] as? [String:Any],
                          let id = turn["id"] as? String,!id.isEmpty,id != previousTurn,
                          let status = turn["status"] as? String else {
                        throw PetFailure(message:"Codex 未返回新轮次的确认信息。")
                    }
                    return Receipt(turnID:id,status:status)
                } catch {throw Unconfirmed(underlying:error)}
            }
            DispatchQueue.main.async {completion(result)}
        }
    }
}
