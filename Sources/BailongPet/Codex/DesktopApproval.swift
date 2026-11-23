import Foundation

struct DesktopApproval {
    let thread:String, turn:String, source:String, method:String
    let requestID:Any
    let params:[String:Any]
    let details:String
    struct DetailSection {let key:String, title:String, text:String, codeLanguage:String?}
    let detailSections:[DetailSection]
    private var hookDecision:((DesktopPermissionHook.Decision?)->Bool)?
    var isHook:Bool {hookDecision != nil}
    func handoffToCodex() {_ = hookDecision?(nil)}
    let canAllow:Bool
    var identity:String {source+":"+thread+":"+turn+":"+String(describing:requestID)}
    var allowTitle:String {method == "item/permissions/requestApproval" ? L10n.text(.tasks,"desktopApproval.handoffToCodex.text") : L10n.text(.tasks,"desktopApproval.handoffToCodex.text.2")}
    var attention:TaskAttention {.init(kind:.approval,body:method == "item/permissions/requestApproval" ? L10n.text(.tasks,"desktopApproval.handoffToCodex.text.3") : method == "item/fileChange/requestApproval" ? L10n.text(.tasks,"desktopApproval.handoffToCodex.text.4") : L10n.text(.tasks,"desktopApproval.handoffToCodex.text.5"))}
    init?(thread:String,turn:String,source:String,request:[String:Any],conversation:[String:Any]) {
        guard let method = request["method"] as? String,let id = request["id"],id is String || id is NSNumber,
              let params = request["params"] as? [String:Any],params["turnId"] as? String == turn else {return nil}
        self.thread = thread; self.turn = turn; self.source = source; self.method = method; requestID = id; self.params = params
        let items = DesktopRuntimeProjection.findTurn(conversation,turn)?["items"] as? [[String:Any]] ?? []
        let item = items.first {$0["id"] as? String == params["itemId"] as? String && params["itemId"] is String}
        var display = params.filter {!["threadId","turnId","itemId","availableDecisions"].contains($0.key) && !($0.value is NSNull)}
        if display["command"] == nil,let command = item?["command"] as? String {display["command"] = command}
        if let changes = item?["changes"] {display["changes"] = changes}
        let available = params["availableDecisions"] as? [Any]
        let acceptsOnce = available == nil || available!.contains {($0 as? String) == "accept"}
        switch method {
        case "item/commandExecution/requestApproval":canAllow = acceptsOnce && (display["command"] as? String)?.isEmpty == false
        case "item/fileChange/requestApproval":canAllow = acceptsOnce && display["changes"] != nil
        case "item/permissions/requestApproval":canAllow = params["permissions"] is [String:Any]
        default:return nil
        }
        let labels = ["reason":L10n.text(.tasks,"desktopApproval.labels"),"command":L10n.text(.tasks,"desktopApproval.labels.2"),"cwd":L10n.text(.tasks,"desktopApproval.labels.3"),"changes":L10n.text(.tasks,"desktopApproval.labels.4"),"permissions":L10n.text(.tasks,"desktopApproval.labels.5"),"additionalPermissions":L10n.text(.tasks,"desktopApproval.labels.6"),"networkApprovalContext":L10n.text(.tasks,"desktopApproval.labels.7"),"grantRoot":L10n.text(.tasks,"desktopApproval.labels.8")]
        let order = ["reason","command","cwd","changes","permissions","additionalPermissions","networkApprovalContext","grantRoot"]
        let keys = order.filter {display[$0] != nil}+display.keys.filter {!order.contains($0)}.sorted()
        detailSections = keys.map {key in
            let value = display[key]!
            let text:String
            if let string = value as? String {text = string}
            else if let data = try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys,.fragmentsAllowed]) {text = String(decoding:data,as:UTF8.self)}
            else {text = String(describing:value)}
            return DetailSection(key:key,title:labels[key] ?? key,text:text,codeLanguage:key == "command" ? "shell" : value is String ? nil : "json")
        }
        details = detailSections.map {$0.title+"\n"+$0.text}.joined(separator:"\n\n")
    }
    init(hook:DesktopPermissionHook.Request,id:UUID,decide:@escaping (DesktopPermissionHook.Decision?)->Bool) {
        thread = hook.thread; turn = hook.turn; source = "PermissionRequest"; method = "Bash"
        requestID = id.uuidString; params = [:]; canAllow = true; hookDecision = decide
        var sections = [DetailSection(key:"command",title:L10n.text(.tasks,"desktopApproval.labels.2"),text:hook.command,codeLanguage:"shell"),
                        DetailSection(key:"cwd",title:L10n.text(.tasks,"desktopApproval.title"),text:hook.cwd,codeLanguage:nil)]
        if let reason = hook.reason,!reason.isEmpty {sections.append(.init(key:"description",title:L10n.text(.tasks,"desktopApproval.labels"),text:reason,codeLanguage:nil))}
        detailSections = sections; details = sections.map {$0.title+"\n"+$0.text}.joined(separator:"\n\n")
    }
    // 用户明确点击后才调用；新连接读取原 owner 的最新快照，再提交完全相同的请求。
    func submit(allow:Bool,completion:@escaping (Error?) -> Void) {
        if let hookDecision {
            let sent = hookDecision(allow ? .allow : .deny)
            completion(sent ? nil : PetFailure(message:L10n.text(.tasks,"desktopApproval.submit.message")))
            return
        }
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let connection = try DesktopSocket(timeoutSeconds:4)
                let initial = try connection.call("initialize",params:["clientType":"bailong-pet"],version:0)
                guard let client = (initial["result"] as? [String:Any])?["clientId"] as? String else {throw PetFailure(message:L10n.text(.tasks,"desktopApproval.submit.message.2"))}
                connection.clientID = client
                let owner = try connection.call("thread-owner-discovery",params:["hostId":"local","conversationId":thread],version:1)
                guard owner["handledByClientId"] as? String == source else {throw PetFailure(message:L10n.text(.tasks,"desktopApproval.submit.message.3"))}
                let before = try snapshot(connection)
                guard let request = (before["requests"] as? [[String:Any]])?.first(where:{String(describing:$0["id"] ?? "") == String(describing:requestID)}),
                      let current = DesktopApproval(thread:thread,turn:turn,source:source,request:request,conversation:before),
                      current.identity == identity,current.method == method,current.details == details,
                      (!allow || current.canAllow),
                      let status = DesktopRuntimeProjection.findTurn(before,turn)?["status"] as? String,activeStatuses.contains(status) else {
                    throw PetFailure(message:L10n.text(.tasks,"desktopApproval.submit.message.4"))
                }
                let route:String
                var body:[String:Any] = ["conversationId":thread,"requestId":requestID]
                switch method {
                case "item/commandExecution/requestApproval":route = "thread-follower-command-approval-decision"; body["decision"] = allow ? "accept" : "decline"
                case "item/fileChange/requestApproval":route = "thread-follower-file-approval-decision"; body["decision"] = allow ? "accept" : "decline"
                default:route = "thread-follower-permissions-request-approval-response"; body["response"] = ["permissions":allow ? params["permissions"] as? [String:Any] ?? [:] : [:],"scope":"turn"]
                }
                do {
                    _ = try connection.call(route,params:body,version:1,target:source)
                    let after = try snapshot(connection)
                    guard !(after["requests"] as? [[String:Any]] ?? []).contains(where:{String(describing:$0["id"] ?? "") == String(describing:requestID)}) else {
                        throw PetFailure(message:L10n.text(.tasks,"desktopApproval.submit.message.5"))
                    }
                } catch {throw PetFailure(message:L10n.text(.tasks,"desktopApproval.submit.message.6")+error.localizedDescription)}
                DispatchQueue.main.async {completion(nil)}
            } catch {DispatchQueue.main.async {completion(error)}}
        }
    }
    private func snapshot(_ connection:DesktopSocket) throws -> [String:Any] {
        // 先排空此前快照；随后请求的新快照才用于点击校验或提交回执。
        let drainDeadline = Date().addingTimeInterval(0.1)
        while Date() < drainDeadline,let _ = try connection.receiveIfAvailable(milliseconds:0) {}
        try connection.broadcast("thread-stream-following-changed",params:["hostId":"local","conversationId":thread,"following":true],version:1)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            guard let frame = try connection.receiveIfAvailable(milliseconds:50) else {continue}
            guard frame["sourceClientId"] as? String == source,frame["method"] as? String == "thread-stream-state-changed",
                  let version = frame["version"] as? Int,DesktopApprovalReader.supportedStreamVersions.contains(version),
                  let p = frame["params"] as? [String:Any],p["hostId"] as? String == "local",p["conversationId"] as? String == thread,
                  let change = p["change"] as? [String:Any],change["type"] as? String == "snapshot",let value = change["conversationState"] as? [String:Any] else {continue}
            return DesktopRuntimeProjection.conversation(value,keepingTurns:[turn])
        }
        throw PetFailure(message:L10n.text(.tasks,"desktopApproval.snapshot.message"))
    }
}

final class ApprovalPresentation {
    let request:DesktopApproval
    var isSubmitting = false
    var error:String?
    var submitted = false
    var ready:Bool {!isSubmitting && error == nil && !submitted}
    init(_ request:DesktopApproval) {self.request = request}
    var body:String {
        [request.details.isEmpty ? request.attention.body : request.details,statusText].filter {!$0.isEmpty}.joined(separator:"\n\n")
    }
    var statusText:String {[request.canAllow ? "" : L10n.text(.tasks,"desktopApproval.text"),error ?? "",isSubmitting ? L10n.text(.tasks,"desktopApproval.text.2") : submitted ? L10n.text(.tasks,"desktopApproval.text.3") : ""].filter {!$0.isEmpty}.joined(separator:"\n\n")}
}
