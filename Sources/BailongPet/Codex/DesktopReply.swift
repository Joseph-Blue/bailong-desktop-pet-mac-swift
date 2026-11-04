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
        var errorDescription:String? {"Codex 尚未加载这条会话，请在 Codex 中打开。"}
    }
    private static func connect(thread:String,timeout:Int = 8) throws -> (DesktopSocket,String) {
        let connection = try DesktopSocket(timeoutSeconds:timeout)
        let initialized = try connection.call("initialize",params:["clientType":"bailong-pet"],version:0)
        guard let client = (initialized["result"] as? [String:Any])?["clientId"] as? String else {throw PetFailure(message:"Codex 未返回本机连接标识。")}
        connection.clientID = client
        let owner:[String:Any]
        do {owner = try connection.call("thread-owner-discovery",params:["hostId":"local","conversationId":thread],version:1)}
        catch let error as DesktopSocket.RequestFailure where error.code == "no-client-found" {throw OwnerUnavailable()}
        guard let target = owner["handledByClientId"] as? String else {throw OwnerUnavailable()}
        return (connection,target)
    }
    struct Settings {
        let model:String
        let effort:String?
        let effortFromHistory:Bool
    }
    static func readSettings(thread:String,completion:@escaping (Result<Settings,Error>) -> Void) {
        DispatchQueue.global(qos:.utility).async {
            let result = Result<Settings,Error> {
                let (connection,target) = try connect(thread:thread)
                let response = try connection.call("thread-follower-read-model-settings",params:["conversationId":thread],version:1,target:target)
                guard let result = response["result"] as? [String:Any],let settings = result["settings"] as? [String:Any],
                      let model = settings["model"] as? String,!model.isEmpty else {throw PetFailure(message:"Codex 未提供当前会话的模型设置。")}
                let liveEffort = settings["reasoningEffort"] as? String
                let recordedEffort = liveEffort == nil ? try DesktopHistoryReader.recordedReasoningEffort(thread:thread,model:model) : nil
                return Settings(model:model,effort:liveEffort ?? recordedEffort,effortFromHistory:recordedEffort != nil)
            }
            DispatchQueue.main.async {completion(result)}
        }
    }
    struct Receipt {
        let turnID:String
        let status:String
    }
    struct Unconfirmed: LocalizedError {
        let underlying:Error
        var errorDescription:String? {"发送结果尚未确认。请打开 Codex 检查原会话，确认未发送后再重试。\n\n"+underlying.localizedDescription}
    }
    static func submit(thread:String,previousTurn:String,cwd:String,text:String,mode:Mode,completion:@escaping (Result<Receipt,Error>) -> Void) {
        DispatchQueue.global(qos:.userInitiated).async {
            let result = Result<Receipt,Error> {
                let (connection,target) = try connect(thread:thread,timeout:30)
                // 紧接发送前重新检查数据库，仅投影身份与状态，不读取对话或凭证。
                try DesktopHistoryReader.requireReplyConversation(thread,previousTurn:previousTurn,steering:mode == .steer)
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
