import Foundation

// 只投影 UI 所需字段；明确排除 reasoning.content、工具输出、用户输入和会话设置。
enum DesktopRuntimeProjection {
    static let requestFields:Set<String> = ["threadId","turnId","itemId","reason","command","cwd","availableDecisions","permissions","additionalPermissions","networkApprovalContext","grantRoot"]
    static let itemFields:Set<String> = ["id","type","status","completed","completedAtMs","summary","tool","server","namespace","command","commandActions","changes","query"]
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
    static func turn(_ raw:Any) -> [String:Any] {
        let raw = raw as? [String:Any] ?? [:]
        var result = raw.filter {["turnId","status"].contains($0.key)}
        result["items"] = (raw["items"] as? [Any] ?? []).map(item)
        return result
    }
    static func conversation(_ raw:[String:Any]) -> [String:Any] {
        let history = (raw["turnHistory"] as? [String:Any])?["history"] as? [String:Any] ?? [:]
        let entities = history["entitiesByKey"] as? [String:Any] ?? [:]
        return ["requests":(raw["requests"] as? [Any] ?? []).map(request),
                "turns":(raw["turns"] as? [Any] ?? []).map(turn),
                "turnHistory":["history":["entitiesByKey":entities.mapValues(turn)]]]
    }
    static func findTurn(_ state:[String:Any],_ id:String) -> [String:Any]? {
        let history = (state["turnHistory"] as? [String:Any])?["history"] as? [String:Any]
        if let value = (history?["entitiesByKey"] as? [String:[String:Any]])?.values.first(where:{$0["turnId"] as? String == id}) {return value}
        return (state["turns"] as? [[String:Any]])?.first {$0["turnId"] as? String == id}
    }
    static func patch(_ patch:[String:Any],state:inout [String:Any]) throws {
        guard let path = patch["path"] as? [Any],let operation = patch["op"] as? String else {throw PetFailure(message:"Codex 实时状态增量格式不兼容。")}
        if path.isEmpty,let raw = patch["value"] as? [String:Any] {state = conversation(raw); return}
        var value = patch["value"] ?? NSNull()
        if path.first as? String == "requests" {
            if path.count == 1 {value = (value as? [Any] ?? []).map(request)}
            else if path.count == 2 {value = request(value)}
            else if path[2] as? String == "params" {
                if path.count == 3 {value = (value as? [String:Any] ?? [:]).filter {requestFields.contains($0.key)}}
                else if !requestFields.contains(path[3] as? String ?? "") {return}
            } else if !["id","method"].contains(path[2] as? String ?? "") {return}
        } else {
            let offset:Int
            if path.first as? String == "turns" {
                if path.count == 1 {value = (value as? [Any] ?? []).map(turn); offset = path.count}
                else {offset = 2}
            } else if path.first as? String == "turnHistory" {
                if path.count < 4 {
                    // 历史结构整体替换时只保留投影字段。
                    if path.count == 1 {value = conversation(["turnHistory":value])["turnHistory"]!}
                    else if path.count == 2,path[1] as? String == "history" {
                        value = (conversation(["turnHistory":["history":value]])["turnHistory"] as! [String:Any])["history"]!
                    } else if path.count == 3,path[2] as? String == "entitiesByKey" {value = (value as? [String:Any] ?? [:]).mapValues(turn)}
                    else {return}
                    offset = path.count
                } else {
                    guard path[1] as? String == "history",path[2] as? String == "entitiesByKey" else {return}
                    offset = 4
                }
            } else {return}
            if path.count == offset && ((path.first as? String == "turns" && offset == 2) || (path.first as? String == "turnHistory" && offset == 4)) {value = turn(value)}
            else if path.count > offset {
                let field = path[offset] as? String ?? ""
                if field == "items" {
                    if path.count == offset+1 {value = (value as? [Any] ?? []).map(item)}
                    else if path.count == offset+2 {value = item(value)}
                    else if !itemFields.contains(path[offset+2] as? String ?? "") {return}
                } else if !["turnId","status"].contains(field) {return}
            }
        }
        var root:Any = state
        try apply(&root,path:ArraySlice(path),operation:operation,value:value)
        guard let result = root as? [String:Any] else {throw PetFailure(message:"Codex 实时状态根节点无效。")}
        state = result
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
