import Foundation

// 普通回复由桌面端原会话处理；不复用桌宠内置任务的人格、模型及权限参数。
enum DesktopReply {
    enum Mode {case start, steer}
    static func mode(for status:String) -> Mode? {
        if ["inProgress","running"].contains(status) {return .steer}
        if TaskOutcome.terminalStatuses.contains(status) {return .start}
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
    private static func isOwnerWakeupBroadcast(_ value:[String:Any],thread:String) -> Bool {
        guard let method = value["method"] as? String,
              let params = value["params"] as? [String:Any],
              params["conversationId"] as? String == thread else {return false}
        if method == "thread-stream-following-status-requested" {return true}
        return method == "thread-stream-state-changed" && params["change"] is [String:Any]
    }
    private static func connect(thread:String,timeout:Int = 8,deadline:Date? = nil,discoveryDeadline:Date? = nil,wakeOnOwnerBroadcast:Bool = false) throws -> (DesktopSocket,String) {
        let probeDeadline = discoveryDeadline ?? deadline
        let connection = try initialize(timeout:timeout,deadline:probeDeadline)
        func discover(deadline currentDeadline:Date?,allowWakeup:Bool) throws -> String {
            let owner:[String:Any]
            do {
                owner = try connection.call("thread-owner-discovery",params:["hostId":"local","conversationId":thread],version:1,
                    deadline:currentDeadline,wakeup:allowWakeup ? {isOwnerWakeupBroadcast($0,thread:thread)} : nil)
            } catch let error as DesktopSocket.RequestFailure where error.code == "no-client-found" {throw OwnerUnavailable()}
            guard let target = owner["handledByClientId"] as? String else {throw OwnerUnavailable()}
            return target
        }
        do {
            return (connection,try discover(deadline:probeDeadline,allowWakeup:wakeOnOwnerBroadcast))
        } catch is DesktopSocket.WakeupInterrupt {
            let retryDeadline = min(deadline ?? .distantFuture,Date().addingTimeInterval(1.5))
            return (connection,try discover(deadline:retryDeadline,allowWakeup:false))
        }
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
        var serviceTier:String? = nil
        var modelProvider:String? = nil
    }
    struct PreparedConnection {
        let settings:Settings
        fileprivate let thread:String
        fileprivate let socket:DesktopSocket
        fileprivate let owner:String
    }
    static func prepareConnection(thread:String,timeout:Int = 12,discoveryTimeout:TimeInterval? = nil,wakeOnOwnerBroadcast:Bool = false,qos:DispatchQoS.QoSClass = .utility,completion:@escaping (Result<PreparedConnection,Error>) -> Void) {
        DispatchQueue.global(qos:qos).async {
            let result = Result<PreparedConnection,Error> {
                let deadline = Date().addingTimeInterval(Double(timeout))
                let discoveryDeadline = discoveryTimeout.map {min(deadline,Date().addingTimeInterval($0))} ?? deadline
                let (connection,target) = try connect(thread:thread,timeout:30,deadline:deadline,discoveryDeadline:discoveryDeadline,wakeOnOwnerBroadcast:wakeOnOwnerBroadcast)
                let response = try connection.call("thread-follower-read-model-settings",params:["conversationId":thread],version:1,target:target,deadline:deadline)
                guard let result = response["result"] as? [String:Any],let settings = result["settings"] as? [String:Any],
                      let model = settings["model"] as? String,!model.isEmpty else {throw PetFailure(message:"Codex 未提供当前会话的模型设置。")}
                let liveEffort = settings["reasoningEffort"] as? String
                let recordedEffort = liveEffort == nil ? try DesktopHistoryReader.recordedReasoningEffort(thread:thread,model:model) : nil
                // read-model-settings v1 不返回速度；从同一 owner 的实时快照读取，不能按模型名推断。
                let tier = try readServiceTier(connection,thread:thread,owner:target,deadline:min(deadline,Date().addingTimeInterval(3)))
                return PreparedConnection(settings:Settings(model:model,effort:liveEffort ?? recordedEffort,effortFromHistory:recordedEffort != nil,
                    serviceTier:tier,modelProvider:settings["modelProvider"] as? String),thread:thread,socket:connection,owner:target)
            }
            DispatchQueue.main.async {completion(result)}
        }
    }
    private static func readServiceTier(_ connection:DesktopSocket,thread:String,owner:String,deadline:Date) throws -> String? {
        try connection.broadcast("thread-stream-following-changed",params:["hostId":"local","conversationId":thread,"following":true],version:1)
        while Date() < deadline {
            guard let frame = try connection.receiveIfAvailable(milliseconds:50),
                  frame["type"] as? String == "broadcast",frame["method"] as? String == "thread-stream-state-changed",
                  frame["sourceClientId"] as? String == owner,
                  let params = frame["params"] as? [String:Any],params["hostId"] as? String == "local",
                  params["conversationId"] as? String == thread else {continue}
            guard let version = frame["version"] as? Int,DesktopApprovalReader.supportedStreamVersions.contains(version) else {
                throw PetFailure(message:"Codex 会话速度状态协议不兼容。")
            }
            guard let change = params["change"] as? [String:Any],change["type"] as? String == "snapshot",
                  let state = change["conversationState"] as? [String:Any] else {continue}
            let tier = serviceTier(in:state)
            try connection.broadcast("thread-stream-following-changed",params:["hostId":"local","conversationId":thread,"following":false],version:1)
            return tier
        }
        throw PetFailure(message:"未收到 Codex 原会话的速度设置。")
    }
    static func serviceTier(in state:[String:Any]) -> String? {
        if let settings = state["latestThreadSettings"] as? [String:Any],let tier = settings["serviceTier"] {
            return tier as? String // 显式 null 清除快速档，不回退到旧轮次。
        }
        let turns:[[String:Any]]
        if let turnHistory = state["turnHistory"] as? [String:Any],turnHistory["kind"] as? String == "canonical",
           let history = turnHistory["history"] as? [String:Any],let islands = history["islands"] as? [[String:Any]],
           let entities = history["entitiesByKey"] as? [String:[String:Any]] {
            turns = islands.flatMap {($0["entries"] as? [[String:Any]] ?? []).compactMap {entry in
                (entry["value"] as? String).flatMap {entities[$0]}
            }}
        } else {turns = state["turns"] as? [[String:Any]] ?? []}
        let params = turns.last(where:{$0["turnId"] is String})?["params"] as? [String:Any]
        return params?["serviceTierForTurn"] as? String ?? params?["serviceTier"] as? String
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
                    else {(connection,target) = try connect(thread:thread,timeout:30,deadline:min(connectionDeadline,Date().addingTimeInterval(2)),wakeOnOwnerBroadcast:true)}
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
