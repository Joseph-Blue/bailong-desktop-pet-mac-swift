import AppKit

struct PlaybackSettingsError: LocalizedError {
    let key:String
    var errorDescription:String? {"播放设置「"+key+"」无效。"}
}

enum SettingsSection: Int, CaseIterable {
    case general, identity, activity, messages, appearance, advanced, developer, updates, about
    var title: String { ["通用","称呼与个性","动作与活动","消息与提醒","外观","高级","性能","更新","关于"][rawValue] }
    var symbol: String { ["gearshape","person.crop.circle","figure.walk","bubble.left.and.bubble.right","paintpalette","slider.horizontal.3","speedometer","arrow.triangle.2.circlepath","info.circle"][rawValue] }
    var keys: [String] {
        switch self {
        case .general: return ["showOnLaunch","rememberPosition","preferredDisplay","autoFullscreen"]
        case .identity: return ["ownerName","customAddress","petName","greetingTemplate","customLines","taskProgressTemplate","taskUpdateTemplate","taskThinkingTemplate","taskToolTemplate","taskCommandTemplate","taskCommandCompletedTemplate","taskSuccessTemplate","taskFailureTemplate","taskInterruptedTemplate","quotaLoadingTemplate","taskAnswerTemplate","taskApprovalTemplate"] + ConversationLines.keys
        case .activity: return ["singleClickAction","doubleClickAction","rightDoubleClickAction","leisureInterval","autoMove","movementRange","avoidRepeat","playbackSpeed","animationWeights","animationSpeeds","favorites","taskOpening","taskCelebration"]
        case .messages: return ["taskReminderEnabled","taskReminderMinutes","approvalButtonOrder","bubbleCardLimit","recentTaskCount","showTaskOverview","showThinkingProgress","showToolProgress","progressToastEnabled","progressToastSeconds","recordHistory","sendShortcut","taskBubbles","progressBubbles","resultBubbles","interactionBubbles","interactionSeconds","progressSeconds","resultSeconds","quotaSeconds","autoReadTime","pauseOnHover","countAfterReveal","typingEffect","soundEnabled","quietCompanion","quietSchedule","quietStart","quietEnd"]
        case .appearance: return ["petPercent","petShadow","bubblePercent","bubbleAspectEnabled","bubbleAspectRatio","messageFontSize","appearanceMode","accentStyle","accentRGB","bubbleMaterial","glassFollowsSystem","glassOpacity","bubbleMotion"]
        case .advanced: return ["defaultWorkspace"]
        case .about: return []
        case .updates: return ["automaticallyCheckUpdates"]
        case .developer: return ["showDiagnostics","diagnosticsPinned","preloadWholeAnimation","animationBufferFrames","animationQuality","animationFPSLimit"]
        }
    }
}

enum MessagePurpose { case interaction, progress, result, attention, quota, preview }
enum AnimationSelection { case general, idle, docked, task }

enum SendShortcut: String, CaseIterable {
    case commandReturn, returnToSend, controlOrCommandReturn
    var sendLabel: String {
        switch self {
        case .commandReturn:return "⌘ Command + ↩ Enter"
        case .returnToSend:return "↩ Enter"
        case .controlOrCommandReturn:return "⌃ Control + ↩ Enter 或 ⌘ Command + ↩ Enter"
        }
    }
    var newlineLabel: String {self == .returnToSend ? "⇧ Shift + ↩ Enter，或 ⌥ Option + ↩ Enter" : "↩ Enter"}
    var hint: String {"发送：\(sendLabel)\n换行：\(newlineLabel)"}
    static var options:[(String,String)] {allCases.map {($0.rawValue,$0.sendLabel+" 发送")}}
    static var settingsExplanation:String {
        allCases.enumerated().map {index,value in
            "\(index == 0 ? "默认" : "备选 \(index)")：\(value.sendLabel) 发送；\(value.newlineLabel) 换行。"
        }.joined(separator:"\n")+"\n临时对话、历史对话和问卷输入同步生效，中文输入法选词时不会发送。"
    }
    func action(modifiers: NSEvent.ModifierFlags) -> Bool? {
        let flags = modifiers.intersection([.command,.shift,.option,.control])
        switch self {
        case .commandReturn:
            if flags == .command {return true}
            if flags.isEmpty || flags == .shift || flags == .option {return false}
        case .returnToSend:
            if flags.isEmpty {return true}
            if flags == .shift || flags == .option {return false}
        case .controlOrCommandReturn:
            if flags == .control || flags == .command {return true}
            if flags.isEmpty || flags == .shift || flags == .option {return false}
        }
        return nil
    }
}

// 只管理桌宠自身的偏好；导入、导出和恢复不涉及历史、凭证或 Codex 配置。
final class PetPreferences {
    static let shared = PetPreferences()
    static let didChange = Notification.Name("BailongPreferencesDidChange")
    static let defaults: [String:Any] = [
        "approvalButtonOrder":"rejectLeft","recordHistory":true,"bubbleCardLimit":20,"recentTaskCount":5,"showTaskOverview":true,"showThinkingProgress":true,"showToolProgress":true,"progressToastEnabled":true,"progressToastSeconds":2.0,"taskReminderEnabled":true,"taskReminderMinutes":5.0,
        "automaticallyCheckUpdates":false,"defaultWorkspace":"",
        "bubbleMaterial":glassAvailable ? "glass" : "plain","glassFollowsSystem":true,"glassOpacity":0.5,"bubbleMotion":true,
        "showDiagnostics":false,"diagnosticsPinned":true,"preloadWholeAnimation":false,"animationBufferFrames":12,"animationQuality":"512","animationFPSLimit":"full",
        "showOnLaunch":true,"rememberPosition":true,"preferredDisplay":"","autoFullscreen":true,
        "ownerName":"","customAddress":"","petName":"白龙娘",
        "greetingTemplate":"{用户名}，{桌宠名}已经准备好啦。","customLines":[String:String](),
        "taskProgressTemplate":"{用户名}，我还在留意进展…","taskUpdateTemplate":"{用户名}，我忙到这一步啦…","taskThinkingTemplate":"{桌宠名}正在思考","taskToolTemplate":"{桌宠名}正在调用工具","taskCommandTemplate":"{桌宠名}正在运行命令","taskCommandCompletedTemplate":"{桌宠名}已运行命令","taskSuccessTemplate":"{用户名}，完成啦！",
        "taskFailureTemplate":"{用户名}，这次任务执行失败。","taskInterruptedTemplate":"{用户名}，任务已中断。",
        "quotaLoadingTemplate":"让我看看额度还有多少……",
        "taskAnswerTemplate":"{用户名}，这一步需要你选一下。","taskApprovalTemplate":"{用户名}，这一步需要你批准。",
        "singleClickAction":"random","doubleClickAction":"quota","rightDoubleClickAction":"chat",
        "leisureInterval":15.0,"autoMove":true,"movementRange":"screen","avoidRepeat":true,"playbackSpeed":1.0,
        "animationWeights":[String:Int](),"animationSpeeds":[String:Double](),"favorites":[String](),"taskOpening":true,"taskCelebration":true,
        "sendShortcut":"commandReturn","taskBubbles":true,"progressBubbles":true,"resultBubbles":true,"interactionBubbles":true,
        "interactionSeconds":5.0,"progressSeconds":10.0,"resultSeconds":20.0,"quotaSeconds":5.0,
        "autoReadTime":true,"pauseOnHover":true,"countAfterReveal":true,"typingEffect":true,"soundEnabled":true,
        "quietCompanion":false,"quietSchedule":false,"quietStart":22*60,"quietEnd":8*60,
        "petPercent":100,"petShadow":true,"bubblePercent":100,"bubbleAspectEnabled":false,"bubbleAspectRatio":1.5,"messageFontSize":13.0,"appearanceMode":"system","accentStyle":"system","accentRGB":[149.0/255,61.0/255,150.0/255]
    ].merging(ConversationLines.defaults) {existing,_ in existing}
    static let ranges: [String:ClosedRange<Double>] = [
        "taskReminderMinutes":1...30,"bubbleCardLimit":5...100,"recentTaskCount":1...20,
        "glassOpacity":0...1,"animationBufferFrames":6...240,"leisureInterval":5...180,"playbackSpeed":0.75...1.5,"interactionSeconds":0...60,"progressSeconds":0...60,"progressToastSeconds":1...10,
        "resultSeconds":0...120,"quotaSeconds":0...120,"quietStart":0...1439,"quietEnd":0...1439,
        "petPercent":50...200,"bubblePercent":50...150,"bubbleAspectRatio":0.6...3,"messageFontSize":11...20
    ]
    static var glassAvailable: Bool {
        #if BAILONG_SDK_GLASS
        if #available(macOS 26.0, *) {return true}
        #endif
        return false
    }
    static var glassAvailabilityDescription: String {
        #if BAILONG_SDK_GLASS
        return "macOS 26 起支持液态玻璃材质。"
        #else
        return "此构建未包含液态玻璃，使用普通材质。"
        #endif
    }
    var usesGlass: Bool {Self.glassAvailable && string("bubbleMaterial") == "glass"}
    static let choices = ["approvalButtonOrder":["rejectLeft","allowLeft"],"bubbleMaterial":["glass","plain"],"animationQuality":["720","512","384","256"],"animationFPSLimit":["full","20","15"],"singleClickAction":["none","chat","quota","history","random"],"doubleClickAction":["none","chat","quota","history","random"],"rightDoubleClickAction":["none","chat","quota","history","random"],"sendShortcut":SendShortcut.allCases.map(\.rawValue),"movementRange":["still","nearby","screen"],
        "appearanceMode":AppAppearance.choices.map(\.0),"accentStyle":AppAccent.choices.map(\.0)]
    private(set) var compatibilityNotice:String?
    let defaults: UserDefaults
    init(defaults: UserDefaults = SettingsStorage.defaults) {
        self.defaults = defaults
        guard defaults.integer(forKey:SettingsStorage.schemaKey) <= SettingsStorage.schemaVersion else {return}
        TemplateSyntax.migrateOnce(defaults,keys:SettingsSection.identity.keys.filter {TemplateSyntax.isTemplateKey($0) || $0 == "customLines"})
        let receivedKeys = ["desktopTaskReceivedTemplate","desktopTaskReceivedBodyTemplate"]
        let received = Dictionary(uniqueKeysWithValues:receivedKeys.compactMap {key in defaults.object(forKey:key).map {(key,$0)}})
        for (key,value) in ConversationLines.migrateReceivedLine(received) {defaults.set(value,forKey:key)}
        defaults.removeObject(forKey:"desktopTaskReceivedBodyTemplate")
        defaults.removeObject(forKey:"addressMode")
        if let old = defaults.string(forKey:"animationFPSLimit"), ["24","30"].contains(old) {defaults.set("full",forKey:"animationFPSLimit")}
    }
    func validatePlayback() throws {
        guard defaults.integer(forKey:SettingsStorage.schemaKey) <= SettingsStorage.schemaVersion else {
            throw PetFailure(message:"设置由更新版本的应用保存，请使用新版打开。原配置未修改。")
        }
        var repaired = [String:Any]()
        for key in ["animationQuality","animationFPSLimit"] where !Self.choices[key]!.contains(string(key)) {
            repaired[key] = defaults.object(forKey:key); defaults.removeObject(forKey:key)
        }
        for key in ["animationBufferFrames","playbackSpeed","petPercent","bubblePercent"] {
            let number = number(key)
            if !number.isFinite || !Self.ranges[key]!.contains(number) || (key != "playbackSpeed" && number.rounded() != number) {
                repaired[key] = defaults.object(forKey:key); defaults.removeObject(forKey:key)
            }
        }
        if !repaired.isEmpty {
            defaults.set(repaired,forKey:"compatibilityRecoveredValues")
            compatibilityNotice = "已将不支持的画质、帧率或播放数值恢复为默认值，原值保留在配置兼容备份中。"
        }
    }

    static func displayID(_ screen: NSScreen) -> String {(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""}
    func value(_ key: String) -> Any {defaults.object(forKey:key) ?? Self.defaults[key]!}
    func bool(_ key: String) -> Bool {value(key) as? Bool ?? false}
    func number(_ key: String) -> Double {(value(key) as? NSNumber)?.doubleValue ?? 0}
    func string(_ key: String) -> String {value(key) as? String ?? ""}
    var animationBufferFrames: Int { Int(number("animationBufferFrames")) }
    var defaultWorkspace:URL {
        let path = string("defaultWorkspace")
        return path.isEmpty ? LocalStorage.workspace : URL(fileURLWithPath:path,isDirectory:true).standardizedFileURL
    }
    var animationResolution: Int { Int(string("animationQuality"))! }
    func animationFPS(native: Double) -> Double { string("animationFPSLimit") == "full" ? native : min(native,Double(string("animationFPSLimit"))!) }
    var sendShortcut: SendShortcut {SendShortcut(rawValue:string("sendShortcut")) ?? .commandReturn}
    func set(_ value: Any, for key: String) {defaults.set(TemplateSyntax.migrate([key:value])[key]!,forKey:key); notify([key])}
    private func notify(_ keys: [String]) {
        NotificationCenter.default.post(name:Self.didChange,object:self,userInfo:["keys":keys])
    }
    func reset(_ keys: [String]) {for key in keys {defaults.removeObject(forKey:key)}; notify(keys)}
    var petName: String {let s = string("petName").trimmingCharacters(in:.whitespacesAndNewlines); return s.isEmpty ? "白龙娘" : s}
    // 产品身份固定；petName 只用于角色称呼和互动文案。
    static let productName = "白龙桌宠Swift"
    var appName: String {Self.productName}
    var ownerName:String {
        let name = string("ownerName").trimmingCharacters(in:.whitespacesAndNewlines)
        return name.isEmpty ? "主人" : name
    }
    // 模板自行选择变量；特定称呼留空沿用用户名。
    var address: String {
        let custom = string("customAddress").trimmingCharacters(in:.whitespacesAndNewlines)
        if custom.isEmpty {return ownerName}
        return TemplateSyntax.render(custom,values:["{桌宠名}":petName,"{用户名}":ownerName])
    }
    func template(_ text: String) -> String {
        TemplateSyntax.render(text,values:["{特定称呼}":address,"{桌宠名}":petName,"{用户名}":ownerName])
    }
    func statusLine(_ key:String) -> String {
        let value = string(key)
        return template(value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? Self.defaults[key] as? String ?? "" : value)
    }
    var sensitiveQuestionNotice: String {template("（已隐藏{桌宠名}的敏感信息提问）")}
    var sensitiveInputNotice: String {template("（已隐藏{用户名}的敏感信息输入）")}
    func taskResultLine(_ status:String) -> String {
        statusLine(status == "completed" ? "taskSuccessTemplate" : ["interrupted","cancelled","canceled"].contains(status) ? "taskInterruptedTemplate" : "taskFailureTemplate")
    }
    // 只传入应用自带文案，不对用户消息、模型正文或历史记录做全局替换。
    func templateSource(_ text:String) -> String {text.replacingOccurrences(of:"白龙娘",with:"{桌宠名}").replacingOccurrences(of:"白龙",with:"{桌宠名}").replacingOccurrences(of:"主人",with:"{用户名}")}
    func fixedText(_ text: String) -> String {template(templateSource(text))}
    func line(for clip: Clip) -> String? {
        if let custom = (value("customLines") as? [String:String])?[clip.id], !custom.isEmpty {return template(custom)}
        return clip.line.map(fixedText)
    }
    func setLine(_ text: String, for id: String) {
        var lines = value("customLines") as? [String:String] ?? [:]
        if text.isEmpty {lines.removeValue(forKey:id)} else {lines[id] = text}
        set(lines,for:"customLines")
    }
    func defaultWeight(_ id:String) -> Int {id == "idle" ? 4 : id == "idle2" ? 1 : 3}
    func baseWeight(_ id: String) -> Int {
        (value("animationWeights") as? [String:Int])?[id] ?? defaultWeight(id)
    }
    func weight(_ id: String) -> Double {Double(baseWeight(id)) * (favorites.contains(id) ? 2 : 1)}
    var favorites: [String] {value("favorites") as? [String] ?? []}
    func setWeight(_ weight: Int, for id: String) {var map = value("animationWeights") as? [String:Int] ?? [:]; map[id] = weight; set(map,for:"animationWeights")}
    func clipSpeed(_ id: String) -> Double {(value("animationSpeeds") as? [String:Double])?[id] ?? 1}
    func speed(_ id: String) -> Double {number("playbackSpeed") * clipSpeed(id)}
    func setSpeed(_ speed: Double, for id: String) {var map = value("animationSpeeds") as? [String:Double] ?? [:]; map[id] = speed; set(map,for:"animationSpeeds")}
    func choose(_ clips: [Clip], previous: String?, selection:AnimationSelection = .general) -> Clip? {
        let pool = clips.filter {weight($0.id) > 0}
        // 原作普通待机 4:1、吸边 7:3、任务组内均匀；手动频率与偏爱按比例调整。
        // 任务候选由调用方先排除上一动作；减少重复只用于其他随机互动。
        func adjusted(_ clip: Clip) -> Double {
            let weight = weight(clip.id)
            switch selection {
            case .idle: return weight
            case .docked: return weight / Double(defaultWeight(clip.id)) * (clip.id == "idle" ? 7 : 3)
            case .task: return weight / Double(defaultWeight(clip.id))
            case .general: return weight * (bool("avoidRepeat") && pool.count > 1 && clip.id == previous ? 0.35 : 1)
            }
        }
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
        return try JSONSerialization.data(withJSONObject:["schemaVersion":SettingsStorage.schemaVersion,"settings":values],options:[.prettyPrinted,.sortedKeys])
    }
    func importData(_ data: Data, clipIDs: Set<String>) throws {
        guard let document = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let schema = document["schemaVersion"] as? Int,var values = document["settings"] as? [String:Any] else {
            throw PetFailure(message:"请选择本应用导出的设置文件。")
        }
        guard (1...SettingsStorage.schemaVersion).contains(schema) else {
            throw PetFailure(message:"不支持设置格式 \(schema)，请使用对应版本的应用。尚未导入任何更改。")
        }
        values = TemplateSyntax.migrate(values)
        values = ConversationLines.migrateReceivedLine(values)
        values.removeValue(forKey:"addressMode")
        if let old = values["animationFPSLimit"] as? String, ["24","30"].contains(old) {values["animationFPSLimit"] = "full"}
        for (key,value) in values {
            // dev.7 / dev.8 导出包含旧开关；统一流式后只校验类型，不恢复旧播放策略。
            if key == "lowResourceMode", let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { continue }
            guard let baseline = Self.defaults[key], Self.valid(value,key:key,baseline:baseline,clipIDs:clipIDs) else {
                throw PetFailure(message:"设置项「\(key)」不受支持或数值超出范围，尚未导入任何更改。")
            }
        }
        // 全部验证后才一次应用；未提供的已知设置回到默认值。
        for key in Self.defaults.keys {defaults.removeObject(forKey:key)}
        for (key,value) in values where key != "lowResourceMode" {defaults.set(value,forKey:key)}
        notify(Array(Self.defaults.keys))
    }
    private static func valid(_ value: Any, key: String, baseline: Any, clipIDs: Set<String>) -> Bool {
        if key == "defaultWorkspace",let path = value as? String {return path.isEmpty || (path.hasPrefix("/") && !path.contains("\0") && path.utf8.count <= 4096)}
        if key == "animationWeights", let map = value as? [String:NSNumber] {
            return map.allSatisfy {clipIDs.contains($0.key) && CFGetTypeID($0.value) != CFBooleanGetTypeID() && [0,1,3,4,6].contains($0.value.doubleValue) && ($0.key != "idle" || $0.value.intValue > 0)}
        }
        if key == "animationSpeeds", let map = value as? [String:NSNumber] {return map.allSatisfy {clipIDs.contains($0.key) && CFGetTypeID($0.value) != CFBooleanGetTypeID() && [0.75,1,1.25,1.5].contains($0.value.doubleValue)}}
        if key == "customLines", let map = value as? [String:String] {return map.allSatisfy {clipIDs.contains($0.key) && TemplateSyntax.count($0.value) <= 120}}
        if key == "favorites", let list = value as? [String] {return list.allSatisfy {clipIDs.contains($0)}}
        if key == "accentRGB", let rgb = value as? [NSNumber] {return rgb.count == 3 && rgb.allSatisfy {CFGetTypeID($0) != CFBooleanGetTypeID() && (0...1).contains($0.doubleValue)}}
        if let range = ranges[key], let n = value as? NSNumber {
            let integer = ["bubbleCardLimit","recentTaskCount","petPercent","bubblePercent","quietStart","quietEnd","animationBufferFrames"].contains(key)
            return CFGetTypeID(n) != CFBooleanGetTypeID() && range.contains(n.doubleValue) && (!integer || n.doubleValue.rounded() == n.doubleValue)
        }
        if let b = baseline as? NSNumber, CFGetTypeID(b) == CFBooleanGetTypeID() {return (value as? NSNumber).map {CFGetTypeID($0) == CFBooleanGetTypeID()} ?? false}
        if baseline is String, let s = value as? String {return (TemplateSyntax.isTemplateKey(key) ? TemplateSyntax.count(s) : s.count) <= (key.hasSuffix("Template") ? ConversationLines.limit(key) : ["ownerName","customAddress","petName"].contains(key) ? 20 : 80) && (choices[key]?.contains(s) ?? true)}
        return false
    }
}
