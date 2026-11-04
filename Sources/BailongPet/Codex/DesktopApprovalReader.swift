import Foundation

// 本机桌面端 thread-stream-state-changed v11 / following-changed v1。
// 订阅公开进展和待批准请求；不成为 writer，决定另经用户点击后的原请求提交。
final class DesktopApprovalReader {
    private struct State {
        var source:String
        var revision:Int
        var projection:[String:Any]
        var updatedAt:Date
    }
    private var socket:DesktopSocket?
    private var followed = Set<String>()
    private var targetTurns = [String:Set<String>]()
    private var states = [String:State]()
    private var snapshotRequestedAt = [String:Date]()
    private(set) var unavailableCount = 0
    var knownThreads:Set<String> {Set(states.keys)}
    private(set) var activities = [String:TaskActivity]()

    func close() {socket = nil; followed.removeAll(); targetTurns.removeAll(); states.removeAll(); snapshotRequestedAt.removeAll(); unavailableCount = 0; activities.removeAll()}

    func read(_ records:[PublicSnapshot]) throws -> [String:StateApproval] {
        let active = records.filter {$0.isLatest && activeStatuses.contains($0.status)}
        let wanted = Set(active.map(\.logical))
        guard !wanted.isEmpty else {close(); return [:]}
        let nextTargets = Dictionary(grouping:active,by:\.logical).mapValues {Set($0.map(\.turn))}
        // 切换轮次不能把已裁剪的旧状态当作新目标的完整数据。
        for (id,turns) in nextTargets where targetTurns[id] != turns {
            states.removeValue(forKey:id); snapshotRequestedAt.removeValue(forKey:id)
        }
        targetTurns = nextTargets
        do {
            if socket == nil {
                let connection = try DesktopSocket(timeoutSeconds:2)
                let response = try connection.call("initialize",params:["clientType":"bailong-pet"],version:0)
                guard let id = (response["result"] as? [String:Any])?["clientId"] as? String else {
                    throw PetFailure(message:"Codex 未返回审批观察连接标识。")
                }
                connection.clientID = id; socket = connection
            }
            guard let socket else {return [:]}
            for id in followed.subtracting(wanted) {
                try follow(id,false,socket); states.removeValue(forKey:id); snapshotRequestedAt.removeValue(forKey:id)
            }
            // 有连续、版本匹配的增量时直接复用；静默五秒或首次订阅才请求完整快照。
            let now = Date()
            for id in wanted where Self.needsSnapshot(now:now,updatedAt:states[id]?.updatedAt,requestedAt:snapshotRequestedAt[id]) {
                try follow(id,true,socket)
            }
            followed = wanted
            let deadline = Date().addingTimeInterval(0.15)
            while Date() < deadline,let frame = try socket.receiveIfAvailable(milliseconds:10) {
                try consume(frame,socket)
            }
            states = states.filter {Date().timeIntervalSince($0.value.updatedAt) < 8}
            unavailableCount = wanted.subtracting(states.keys).count
            var result = [String:StateApproval](); activities.removeAll()
            for record in active {
                guard let state = states[record.logical] else {continue}
                if let turn = DesktopRuntimeProjection.findTurn(state.projection,record.turn),let activity = TaskActivity.current(items:turn["items"] as? [[String:Any]] ?? []) {activities[record.key] = activity}
                let requests = (state.projection["requests"] as? [[String:Any]] ?? []).filter {($0["params"] as? [String:Any])?["turnId"] as? String == record.turn}
                if let request = requests.first(where:{Self.methods.contains($0["method"] as? String ?? "")}) {
                    if let approval = DesktopApproval(thread:record.logical,turn:record.turn,source:state.source,request:request,conversation:state.projection) {
                        result[record.key] = StateApproval(id:approval.identity,attention:approval.attention,request:approval)
                    }
                }
            }
            return result
        } catch {close(); throw error}
    }
    struct StateApproval {let id:String; let attention:TaskAttention; let request:DesktopApproval}
    private static let methods:Set<String> = ["item/commandExecution/requestApproval","item/fileChange/requestApproval","item/permissions/requestApproval"]
    static func needsSnapshot(now:Date,updatedAt:Date?,requestedAt:Date?) -> Bool {
        now.timeIntervalSince(max(updatedAt ?? .distantPast,requestedAt ?? .distantPast)) >= 5
    }
    private func follow(_ id:String,_ value:Bool,_ socket:DesktopSocket) throws {
        try socket.broadcast("thread-stream-following-changed",params:["hostId":"local","conversationId":id,"following":value],version:1)
        if value {snapshotRequestedAt[id] = Date()}
    }
    private func consume(_ frame:[String:Any],_ socket:DesktopSocket) throws {
        guard frame["type"] as? String == "broadcast",frame["method"] as? String == "thread-stream-state-changed",
              let params = frame["params"] as? [String:Any],params["hostId"] as? String == "local",
              let id = params["conversationId"] as? String,followed.contains(id),let turns = targetTurns[id] else {return}
        guard frame["version"] as? Int == 11,let source = frame["sourceClientId"] as? String,
              let change = params["change"] as? [String:Any],let revision = change["revision"] as? Int else {
            throw PetFailure(message:"Codex 审批状态协议不兼容。")
        }
        if change["type"] as? String == "snapshot" {
            guard let conversation = change["conversationState"] as? [String:Any],conversation["requests"] is [Any] else {
                throw PetFailure(message:"Codex 审批快照缺少请求列表。")
            }
            states[id] = State(source:source,revision:revision,projection:DesktopRuntimeProjection.conversation(conversation,keepingTurns:turns),updatedAt:Date()); return
        }
        guard change["type"] as? String == "patches",let patches = change["patches"] as? [[String:Any]] else {
            throw PetFailure(message:"Codex 审批增量格式不兼容。")
        }
        guard var state = states[id],state.source == source,state.revision == change["baseRevision"] as? Int else {
            states.removeValue(forKey:id); try follow(id,true,socket); return
        }
        for patch in patches {
            guard try DesktopRuntimeProjection.patch(patch,state:&state.projection,keepingTurns:turns) else {
                states.removeValue(forKey:id); try follow(id,true,socket); return
            }
        }
        state.revision = revision; state.updatedAt = Date(); states[id] = state
    }
}
