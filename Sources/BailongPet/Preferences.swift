import AppKit

enum SettingsSection: Int, CaseIterable {
    case general, identity, activity, messages, appearance, advanced
    var title: String { ["通用","称呼与个性","动作与活动","消息与提醒","外观","高级"][rawValue] }
    var symbol: String { ["gearshape","person.crop.circle","figure.walk","bubble.left.and.bubble.right","paintpalette","slider.horizontal.3"][rawValue] }
    var keys: [String] {
        switch self {
        case .general: return ["showOnLaunch","rememberPosition","preferredDisplay","autoFullscreen"]
        case .identity: return ["ownerName","addressMode","customAddress","petName","greetingTemplate","customLines"]
        case .activity: return ["singleClickAction","doubleClickAction","rightDoubleClickAction","leisureInterval","autoMove","movementRange","avoidRepeat","playbackSpeed","animationWeights","animationSpeeds","favorites","taskOpening","taskCelebration"]
        case .messages: return ["sendShortcut","taskBubbles","progressBubbles","resultBubbles","interactionBubbles","interactionSeconds","progressSeconds","resultSeconds","quotaSeconds","autoReadTime","pauseOnHover","countAfterReveal","typingEffect","soundEnabled","quietCompanion","quietSchedule","quietStart","quietEnd"]
        case .appearance: return ["petPercent","bubblePercent","messageFontSize","appearanceMode","accentStyle","accentRGB"]
        case .advanced: return []
        }
    }
}

enum MessagePurpose { case interaction, progress, result, attention, quota, preview }

enum SendShortcut: String {
    case commandReturn, returnToSend
    var sendLabel: String {self == .commandReturn ? "⌘ Command + ↩ Enter" : "↩ Enter"}
    var newlineLabel: String {self == .commandReturn ? "↩ Enter" : "⇧ Shift + ↩ Enter，或 ⌥ Option + ↩ Enter"}
    var hint: String {"发送：\(sendLabel)\n换行：\(newlineLabel)"}
    func action(modifiers: NSEvent.ModifierFlags) -> Bool? {
        let flags = modifiers.intersection([.command,.shift,.option,.control])
        switch self {
        case .commandReturn:
            if flags == .command {return true}
            if flags.isEmpty || flags == .shift || flags == .option {return false}
        case .returnToSend:
            if flags.isEmpty {return true}
            if flags == .shift || flags == .option {return false}
        }
        return nil
    }
}

// 只管理桌宠自身的偏好；导入、导出和恢复不涉及历史、凭证或 Codex 配置。
final class PetPreferences {
    static let shared = PetPreferences()
    static let didChange = Notification.Name("BailongPreferencesDidChange")
    static let defaults: [String:Any] = [
        "showOnLaunch":true,"rememberPosition":true,"preferredDisplay":"","autoFullscreen":true,
        "ownerName":"","addressMode":"master","customAddress":"","petName":"白龙娘",
        "greetingTemplate":"{称呼}，{桌宠}已经准备好啦。","customLines":[String:String](),
        "singleClickAction":"random","doubleClickAction":"quota","rightDoubleClickAction":"chat",
        "leisureInterval":15.0,"autoMove":true,"movementRange":"screen","avoidRepeat":true,"playbackSpeed":1.0,
        "animationWeights":[String:Int](),"animationSpeeds":[String:Double](),"favorites":[String](),"taskOpening":true,"taskCelebration":true,
        "sendShortcut":"commandReturn","taskBubbles":true,"progressBubbles":true,"resultBubbles":true,"interactionBubbles":true,
        "interactionSeconds":5.0,"progressSeconds":10.0,"resultSeconds":20.0,"quotaSeconds":20.0,
        "autoReadTime":true,"pauseOnHover":true,"countAfterReveal":true,"typingEffect":true,"soundEnabled":true,
        "quietCompanion":false,"quietSchedule":false,"quietStart":22*60,"quietEnd":8*60,
        "petPercent":100,"bubblePercent":100,"messageFontSize":13.0,"appearanceMode":"system","accentStyle":"purple","accentRGB":[0.60,0.40,0.74]
    ]
    static let ranges: [String:ClosedRange<Double>] = [
        "leisureInterval":5...180,"playbackSpeed":0.75...1.5,"interactionSeconds":0...60,"progressSeconds":0...60,
        "resultSeconds":0...120,"quotaSeconds":0...120,"quietStart":0...1439,"quietEnd":0...1439,
        "petPercent":50...200,"bubblePercent":50...150,"messageFontSize":11...20
    ]
    static let choices = ["singleClickAction":["none","chat","quota","history","random"],"doubleClickAction":["none","chat","quota","history","random"],"rightDoubleClickAction":["none","chat","quota","history","random"],"sendShortcut":["commandReturn","returnToSend"],"addressMode":["master","name","custom"],"movementRange":["still","nearby","screen"],
        "appearanceMode":AppAppearance.choices.map(\.0),"accentStyle":AppAccent.choices.map(\.0)]
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {self.defaults = defaults}
    static func displayID(_ screen: NSScreen) -> String {(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""}
    func value(_ key: String) -> Any {defaults.object(forKey:key) ?? Self.defaults[key]!}
    func bool(_ key: String) -> Bool {value(key) as? Bool ?? false}
    func number(_ key: String) -> Double {(value(key) as? NSNumber)?.doubleValue ?? 0}
    func string(_ key: String) -> String {value(key) as? String ?? ""}
    var sendShortcut: SendShortcut {SendShortcut(rawValue:string("sendShortcut")) ?? .commandReturn}
    func set(_ value: Any, for key: String) {defaults.set(value,forKey:key); notify([key])}
    private func notify(_ keys: [String]) {
        NotificationCenter.default.post(name:Self.didChange,object:self,userInfo:["keys":keys])
    }
    func reset(_ keys: [String]) {for key in keys {defaults.removeObject(forKey:key)}; notify(keys)}
    var petName: String {let s = string("petName").trimmingCharacters(in:.whitespacesAndNewlines); return s.isEmpty ? "白龙娘" : s}
    // 产品身份固定；petName 只用于角色称呼和互动文案。
    static let productName = "白龙娘"
    var appName: String {Self.productName+"桌宠MacOS-Swift版"}
    var address: String {
        let key = string("addressMode") == "name" ? "ownerName" : "customAddress"
        if string("addressMode") == "master" {return "主人"}
        let s = string(key).trimmingCharacters(in:.whitespacesAndNewlines)
        return s.isEmpty ? "主人" : s
    }
    func template(_ text: String) -> String {
        text.replacingOccurrences(of:"{称呼}",with:address).replacingOccurrences(of:"{桌宠}",with:petName)
            .replacingOccurrences(of:"{名字}",with:string("ownerName"))
    }
    // 只传入应用自带文案，不对用户消息、模型正文或历史记录做全局替换。
    func fixedText(_ text: String) -> String {template(text.replacingOccurrences(of:"白龙娘",with:"{桌宠}").replacingOccurrences(of:"白龙",with:"{桌宠}").replacingOccurrences(of:"主人",with:"{称呼}"))}
    func line(for clip: Clip) -> String? {
        if let custom = (value("customLines") as? [String:String])?[clip.id], !custom.isEmpty {return template(custom)}
        return clip.line.map(fixedText)
    }
    func setLine(_ text: String, for id: String) {
        var lines = value("customLines") as? [String:String] ?? [:]
        if text.isEmpty {lines.removeValue(forKey:id)} else {lines[id] = text}
        set(lines,for:"customLines")
    }
    func baseWeight(_ id: String) -> Int {
        (value("animationWeights") as? [String:Int])?[id] ?? (id == "idle" ? 4 : id == "idle2" ? 1 : 3)
    }
    func weight(_ id: String) -> Double {Double(baseWeight(id)) * (favorites.contains(id) ? 2 : 1)}
    var favorites: [String] {value("favorites") as? [String] ?? []}
    func setWeight(_ weight: Int, for id: String) {var map = value("animationWeights") as? [String:Int] ?? [:]; map[id] = weight; set(map,for:"animationWeights")}
    func clipSpeed(_ id: String) -> Double {(value("animationSpeeds") as? [String:Double])?[id] ?? 1}
    func speed(_ id: String) -> Double {number("playbackSpeed") * clipSpeed(id)}
    func setSpeed(_ speed: Double, for id: String) {var map = value("animationSpeeds") as? [String:Double] ?? [:]; map[id] = speed; set(map,for:"animationSpeeds")}
    func choose(_ clips: [Clip], previous: String?) -> Clip? {
        let pool = clips.filter {weight($0.id) > 0}
        // 降低刚播放动作的权重，而非强制排除；只有两段待机时也能保留频率差异。
        func adjusted(_ clip: Clip) -> Double {weight(clip.id) * (bool("avoidRepeat") && pool.count > 1 && clip.id == previous ? 0.35 : 1)}
        let total = pool.reduce(0.0) {$0 + adjusted($1)}
        guard total > 0 else {return nil}
        var pick = Double.random(in:0..<total)
        for clip in pool {pick -= adjusted(clip); if pick < 0 {return clip}}
        return pool.last
    }
    func isQuiet(at date: Date = Date()) -> Bool {
        if bool("quietCompanion") {return true}
        guard bool("quietSchedule") else {return false}
        let components = Calendar.current.dateComponents([.hour,.minute],from:date)
        let now = (components.hour ?? 0)*60 + (components.minute ?? 0)
        let start = Int(number("quietStart")), end = Int(number("quietEnd"))
        // 起止相同表示全天，跨午夜时分别覆盖两端。
        return start == end || (start < end ? now >= start && now < end : now >= start || now < end)
    }
    var activityInterval: Double {isQuiet() ? max(60,number("leisureInterval")) : number("leisureInterval")}
    func allows(_ purpose: MessagePurpose) -> Bool {
        switch purpose {
        case .attention, .quota, .preview: return true
        case .interaction: return bool("interactionBubbles") && !isQuiet()
        case .progress: return bool("taskBubbles") && bool("progressBubbles") && !isQuiet()
        case .result: return bool("taskBubbles") && bool("resultBubbles")
        }
    }
    func duration(_ purpose: MessagePurpose, text: String) -> Double {
        switch purpose {
        case .attention: return 0
        case .preview: return 8
        case .interaction: return number("interactionSeconds")
        case .progress: return number("progressSeconds")
        case .quota: return number("quotaSeconds")
        case .result:
            let base = number("resultSeconds")
            return base == 0 ? 0 : bool("autoReadTime") ? max(base,min(120,Double(text.count)/6+3)) : base
        }
    }
    func exportData() throws -> Data {
        let values = Dictionary(uniqueKeysWithValues:Self.defaults.keys.map {($0,value($0))})
        return try JSONSerialization.data(withJSONObject:["schemaVersion":1,"settings":values],options:[.prettyPrinted,.sortedKeys])
    }
    func importData(_ data: Data, clipIDs: Set<String>) throws {
        guard let document = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              document["schemaVersion"] as? Int == 1, let values = document["settings"] as? [String:Any] else {
            throw PetFailure(message:"请选择本应用导出的设置文件。")
        }
        for (key,value) in values {
            guard let baseline = Self.defaults[key], Self.valid(value,key:key,baseline:baseline,clipIDs:clipIDs) else {
                throw PetFailure(message:"设置项「\(key)」不受支持或数值超出范围，尚未导入任何更改。")
            }
        }
        // 全部验证后才一次应用；未提供的已知设置回到默认值。
        for key in Self.defaults.keys {defaults.removeObject(forKey:key)}
        for (key,value) in values {defaults.set(value,forKey:key)}
        notify(Array(Self.defaults.keys))
    }
    private static func valid(_ value: Any, key: String, baseline: Any, clipIDs: Set<String>) -> Bool {
        if key == "animationWeights", let map = value as? [String:NSNumber] {
            return map.allSatisfy {clipIDs.contains($0.key) && CFGetTypeID($0.value) != CFBooleanGetTypeID() && [0,1,3,4,6].contains($0.value.doubleValue) && ($0.key != "idle" || $0.value.intValue > 0)}
        }
        if key == "animationSpeeds", let map = value as? [String:NSNumber] {return map.allSatisfy {clipIDs.contains($0.key) && CFGetTypeID($0.value) != CFBooleanGetTypeID() && [0.75,1,1.25,1.5].contains($0.value.doubleValue)}}
        if key == "customLines", let map = value as? [String:String] {return map.allSatisfy {clipIDs.contains($0.key) && $0.value.count <= 500}}
        if key == "favorites", let list = value as? [String] {return list.allSatisfy {clipIDs.contains($0)}}
        if key == "accentRGB", let rgb = value as? [NSNumber] {return rgb.count == 3 && rgb.allSatisfy {CFGetTypeID($0) != CFBooleanGetTypeID() && (0...1).contains($0.doubleValue)}}
        if let range = ranges[key], let n = value as? NSNumber {
            let integer = ["petPercent","bubblePercent","quietStart","quietEnd"].contains(key)
            return CFGetTypeID(n) != CFBooleanGetTypeID() && range.contains(n.doubleValue) && (!integer || n.doubleValue.rounded() == n.doubleValue)
        }
        if let b = baseline as? NSNumber, CFGetTypeID(b) == CFBooleanGetTypeID() {return (value as? NSNumber).map {CFGetTypeID($0) == CFBooleanGetTypeID()} ?? false}
        if baseline is String, let s = value as? String {return s.count <= (key == "greetingTemplate" ? 500 : 80) && (choices[key]?.contains(s) ?? true)}
        return false
    }
}
