import Foundation

// 只投影 UI 所需字段；明确排除 reasoning.content、工具输出、用户输入和会话设置。
enum DesktopRuntimeProjection {
    static let requestFields:Set<String> = ["threadId","turnId","itemId","reason","command","cwd","availableDecisions","permissions","additionalPermissions","networkApprovalContext","grantRoot"]
    static let itemFields:Set<String> = ["id","type","status","completed","completedAtMs","summary","tool","server","namespace","command","commandActions","changes","query","message","willRetry","errorInfo"]
    static func request(_ raw:Any) -> [String:Any] {
        guard let value = raw as? [String:Any] else {return [:]}
        var result = value.filter {["id","method"].contains($0.key)}
        let method = value["method"] as? String ?? ""
        let fields = method.hasSuffix("/requestApproval") ? requestFields : ["turnId"]
        result["params"] = (value["params"] as? [String:Any] ?? [:]).filter {fields.contains($0.key)}
        return result
    }
    static func item(_ raw:Any) -> [String:Any] {
        (raw as? [String:Any] ?? [:]).filter {itemFields.contains($0.key)}
    }
    private static func turn(_ raw:Any,keepingTurns:Set<String>) -> [String:Any] {
        let raw = raw as? [String:Any] ?? [:]
        var result = raw.filter {["turnId","status"].contains($0.key)}
        if let id = raw["turnId"] as? String,keepingTurns.contains(id) {
            result["items"] = (raw["items"] as? [Any] ?? []).map(item)
        }
        return result
    }
    // 非目标轮次只保留身份和状态；数组槽位与历史键仍在，后续补丁索引不变。
    static func conversation(_ raw:[String:Any],keepingTurns:Set<String>) -> [String:Any] {
        let history = (raw["turnHistory"] as? [String:Any])?["history"] as? [String:Any] ?? [:]
        let entities = history["entitiesByKey"] as? [String:Any] ?? [:]
        return ["requests":(raw["requests"] as? [Any] ?? []).map(request),
                "turns":(raw["turns"] as? [Any] ?? []).map {turn($0,keepingTurns:keepingTurns)},
                "turnHistory":["history":["entitiesByKey":entities.mapValues {turn($0,keepingTurns:keepingTurns)}]]]
    }
    static func findTurn(_ state:[String:Any],_ id:String) -> [String:Any]? {
        let history = (state["turnHistory"] as? [String:Any])?["history"] as? [String:Any]
        if let value = (history?["entitiesByKey"] as? [String:[String:Any]])?.values.first(where:{$0["turnId"] as? String == id}) {return value}
        return (state["turns"] as? [[String:Any]])?.first {$0["turnId"] as? String == id}
    }
    // 只识别模型正文／公开摘要确实变化的增量；不保留被排除的正文内容。
    static func modelProgressTurn(_ patch:[String:Any],state:[String:Any]) -> String? {
        guard let path = patch["path"] as? [Any],patch["op"] as? String != "remove" else {return nil}
        let offset:Int
        if path.first as? String == "turns" {offset = 2}
        else if path.first as? String == "turnHistory" {offset = 4}
        else {return nil}
        guard path.count >= offset+2,path[offset] as? String == "items",
              let rawTurn = try? node(state,path:ArraySlice(path.prefix(offset))),let turn = rawTurn as? [String:Any] else {return nil}
        let item:[String:Any]
        if path.count == offset+2 {item = patch["value"] as? [String:Any] ?? [:]}
        else {
            guard ["text","summary"].contains(path[offset+2] as? String ?? ""),
                  let rawItem = try? node(state,path:ArraySlice(path.prefix(offset+2))),let value = rawItem as? [String:Any] else {return nil}
            item = value
        }
        return CodexConnectionProgress.isModelItem(item) ? turn["turnId"] as? String : nil
    }
    static func errorProgressTurn(_ patch:[String:Any],state:[String:Any]) -> String? {
        guard let path = patch["path"] as? [Any],patch["op"] as? String != "remove" else {return nil}
        let offset:Int
        if path.first as? String == "turns" {offset = 2}
        else if path.first as? String == "turnHistory" {offset = 4}
        else {return nil}
        guard path.count >= offset+2,path[offset] as? String == "items",
              let rawTurn = try? node(state,path:ArraySlice(path.prefix(offset))),let turn = rawTurn as? [String:Any],
              let rawItem = try? node(state,path:ArraySlice(path.prefix(offset+2))),let item = rawItem as? [String:Any],
              item["type"] as? String == "error",item["willRetry"] is Bool else {return nil}
        return turn["turnId"] as? String
    }
    // false 表示补丁将已裁剪的轮次改成目标身份，调用方须取得完整快照。
    static func patch(_ patch:[String:Any],state:inout [String:Any],keepingTurns:Set<String>) throws -> Bool {
        guard let path = patch["path"] as? [Any],let operation = patch["op"] as? String else {throw PetFailure(message:"Codex 实时状态增量格式不兼容。")}
        if path.isEmpty,let raw = patch["value"] as? [String:Any] {state = conversation(raw,keepingTurns:keepingTurns); return true}
        var value = patch["value"] ?? NSNull()
        var changedTurnIdentity = false
        if path.first as? String == "requests" {
            if path.count == 1 {value = (value as? [Any] ?? []).map(request)}
            else if path.count == 2 {value = request(value)}
            else if path[2] as? String == "params" {
                if path.count == 3 {value = (value as? [String:Any] ?? [:]).filter {requestFields.contains($0.key)}}
                else if !requestFields.contains(path[3] as? String ?? "") {return true}
            } else if !["id","method"].contains(path[2] as? String ?? "") {return true}
        } else {
            let offset:Int
            if path.first as? String == "turns" {
                if path.count == 1 {value = (value as? [Any] ?? []).map {turn($0,keepingTurns:keepingTurns)}; offset = path.count}
                else {offset = 2}
            } else if path.first as? String == "turnHistory" {
                if path.count < 4 {
                    // 历史结构整体替换时只保留投影字段。
                    if path.count == 1 {value = conversation(["turnHistory":value],keepingTurns:keepingTurns)["turnHistory"]!}
                    else if path.count == 2,path[1] as? String == "history" {
                        value = (conversation(["turnHistory":["history":value]],keepingTurns:keepingTurns)["turnHistory"] as! [String:Any])["history"]!
                    } else if path.count == 3,path[2] as? String == "entitiesByKey" {value = (value as? [String:Any] ?? [:]).mapValues {turn($0,keepingTurns:keepingTurns)}}
                    else {return true}
                    offset = path.count
                } else {
                    guard path[1] as? String == "history",path[2] as? String == "entitiesByKey" else {return true}
                    offset = 4
                }
            } else {return true}
            if path.count == offset && ((path.first as? String == "turns" && offset == 2) || (path.first as? String == "turnHistory" && offset == 4)) {value = turn(value,keepingTurns:keepingTurns)}
            else if path.count > offset {
                let field = path[offset] as? String ?? ""
                let current = try node(state,path:ArraySlice(path.prefix(offset))) as? [String:Any] ?? [:]
                let retained = (current["turnId"] as? String).map {keepingTurns.contains($0)} ?? false
                changedTurnIdentity = field == "turnId"
                if !retained {
                    if field == "turnId",let id = value as? String,keepingTurns.contains(id) {return false}
                    if !["turnId","status"].contains(field) {return true}
                }
                if field == "items" {
                    if path.count == offset+1 {value = (value as? [Any] ?? []).map(item)}
                    else if path.count == offset+2 {value = item(value)}
                    else if !itemFields.contains(path[offset+2] as? String ?? "") {return true}
                } else if !["turnId","status"].contains(field) {return true}
            }
        }
        var root:Any = state
        try apply(&root,path:ArraySlice(path),operation:operation,value:value)
        guard let result = root as? [String:Any] else {throw PetFailure(message:"Codex 实时状态根节点无效。")}
        state = changedTurnIdentity ? conversation(result,keepingTurns:keepingTurns) : result
        return true
    }
    private static func node(_ node:Any,path:ArraySlice<Any>) throws -> Any {
        guard let head = path.first else {return node}
        if let key = head as? String,let object = node as? [String:Any],let child = object[key] {return try self.node(child,path:path.dropFirst())}
        if let index = head as? Int,let array = node as? [Any],array.indices.contains(index) {return try self.node(array[index],path:path.dropFirst())}
        throw PetFailure(message:"Codex 实时状态路径已变化。")
    }
    private static func apply(_ node:inout Any,path:ArraySlice<Any>,operation:String,value:Any) throws {
        guard let head = path.first else {node = value; return}
        let tail = path.dropFirst()
        if let key = head as? String,var object = node as? [String:Any] {
            if tail.isEmpty {if operation == "remove" {object.removeValue(forKey:key)} else {object[key] = value}}
            else {guard var child = object[key] else {throw PetFailure(message:"Codex 实时状态路径已变化。")}; try apply(&child,path:tail,operation:operation,value:value); object[key] = child}
            node = object
        } else if let index = head as? Int,var array = node as? [Any],index >= 0 {
            if tail.isEmpty && operation == "add",index <= array.count {array.insert(value,at:index)}
            else {
                guard array.indices.contains(index) else {throw PetFailure(message:"Codex 实时状态索引已变化。")}
                if tail.isEmpty && operation == "remove" {array.remove(at:index)}
                else {var child = array[index]; try apply(&child,path:tail,operation:operation,value:value); array[index] = child}
            }
            node = array
        } else {throw PetFailure(message:"Codex 实时状态路径不兼容。")}
    }
}
