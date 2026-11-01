import Foundation

// 台词变量的旧设置迁移；用户名、桌宠名和历史正文保持字面值。
enum TemplateSyntax {
    static let aliases = [("{称呼}","{特定称呼}"),("{名字}","{用户名}"),("{桌宠}","{桌宠名}")]
    static let tokens = ["{用户名}","{桌宠名}","{特定称呼}"]
    static let migrationKey = "templateVariableNamesVersion"
    static func normalized(_ text:String) -> String {
        aliases.reduce(text) {$0.replacingOccurrences(of:$1.0,with:$1.1)}
    }
    static func units(_ text:String) -> [String] {
        var result = [String](), rest = text[...]
        let accepted = tokens+aliases.map(\.0)
        while !rest.isEmpty {
            if let token = accepted.first(where:{rest.hasPrefix($0)}) {result.append(token); rest = rest.dropFirst(token.count)}
            else {result.append(String(rest.removeFirst()))}
        }
        return result
    }
    static func count(_ text:String) -> Int {units(text).count}
    static func bounded(_ text:String,limit:Int) -> String {units(text).prefix(limit).joined()}
    static func render(_ text:String,values:[String:String]) -> String {
        units(normalized(text)).map {values[$0] ?? $0}.joined()
    }
    static func isTemplateKey(_ key:String) -> Bool {key == "customAddress" || key.hasSuffix("Template")}
    static func migrate(_ values:[String:Any]) -> [String:Any] {
        var result = values
        for (key,value) in values {
            if isTemplateKey(key),let text = value as? String {result[key] = normalized(text)}
            else if key == "customLines",let lines = value as? [String:String] {result[key] = lines.mapValues(normalized)}
        }
        return result
    }
    static func migrateOnce(_ defaults:UserDefaults,keys:[String]) {
        guard defaults.integer(forKey:migrationKey) < 2 else {return}
        let values = Dictionary(uniqueKeysWithValues:keys.compactMap {key in defaults.object(forKey:key).map {(key,$0)}})
        for (key,value) in migrate(values) {defaults.set(value,forKey:key)}
        defaults.set(2,forKey:migrationKey)
    }
}
