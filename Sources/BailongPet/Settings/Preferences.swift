import AppKit

enum ProjectSendChannel:String, CaseIterable {
    case modern, legacy

    static let key = "projectSendChannel"
    static let group = L10n.text(.settings,"projectSendChannel.group")
    static let settingTitle = L10n.text(.settings,"projectSendChannel.settingTitle")
    static let legacyVersion = "26.1111.21308"
    static let modernVersion = "26.1117.41037"
    static let modernSeries = "26.1117"
    static let help = L10n.format(.settings,"projectSendChannel.help",String(describing:modernSeries),String(describing:modernVersion),String(describing:modernSeries),String(describing:legacyVersion))
    static func recommended(for version:String?) -> Self {
        guard let version,let current = SemanticVersion(version),
              let cutoff = SemanticVersion(modernSeries+".0") else {return .modern}
        return current < cutoff ? .legacy : .modern
    }
    var title:String {self == .modern ? L10n.text(.settings,"projectSendChannel.option.modern") : L10n.text(.settings,"projectSendChannel.option.legacy")}
    static var options:[(String,String)] {allCases.map {($0.rawValue,$0.title)}}
}

struct PlaybackSettingsError: LocalizedError {
    let key:String
    var errorDescription:String? {L10n.text(.settings,"preferences.playbackSettingsError.text")+key+L10n.text(.settings,"preferences.playbackSettingsError.text.2")}
}

enum SettingsSection: Int, CaseIterable {
    case general, identity, activity, messages, appearance, advanced, developer, updates, about
    var title: String { [L10n.text(.settings,"sections.general"),L10n.text(.settings,"sections.identity"),L10n.text(.settings,"sections.activity"),L10n.text(.settings,"sections.messages"),L10n.text(.settings,"sections.appearance"),L10n.text(.settings,"sections.advanced"),L10n.text(.settings,"sections.performance"),L10n.text(.settings,"sections.updates"),L10n.text(.settings,"search.add.text.118")][rawValue] }
    var symbol: String { ["gearshape","person.crop.circle","figure.walk","bubble.left.and.bubble.right","paintpalette","slider.horizontal.3","speedometer","arrow.triangle.2.circlepath","info.circle"][rawValue] }
    var keys: [String] {
        switch self {
        case .general: return ["rememberPosition","preferredDisplay","autoFullscreen",BrowserSearchEngine.key,ProjectSendChannel.key]
        case .identity: return ["ownerName","customAddress","petName","greetingTemplate","customLines","randomWorkingLines","taskProgressTemplate","taskUpdateTemplate","taskSuccessTemplate","taskFailureTemplate","taskInterruptedTemplate","quotaLoadingTemplate","taskAnswerTemplate","taskApprovalTemplate"] + ConversationLines.keys
        case .activity: return PetGestureSetting.all.map(\.key) + ["dragTiltEnabled","dragTiltIntensity","sideDockEnabled","sideExposurePercent","notchDockEnabled","notchExposurePercent","windowDockEnabled",WindowDockModifier.key,"leisureInterval","autoMove","movementRange","avoidRepeat","playbackSpeed","animationWeights","animationSpeeds","taskOpening","taskCelebration"]
        case .messages: return MessageSettingsPage.preferenceKeys + [PetPreferences.tokenDetailsKey]
        case .appearance: return ["petPercent","bubblePercent","bubbleAspectEnabled","bubbleAspectRatio","messageFontSize","appearanceMode","accentStyle","accentRGB","bubbleMaterial","glassFollowsSystem","glassOpacity",BubbleCloseButtonPosition.key]
        case .advanced: return ["defaultWorkspace"]
        case .about: return []
        case .updates: return ["automaticallyCheckUpdates"]
        case .developer: return ["showDiagnostics","diagnosticsPinned","preloadWholeAnimation","animationBufferFrames","animationQuality","animationFPSLimit","animationOpeningCache","bubbleMotion","animationSmoothTransition","animationEdgeCleanup","petShadow","quotaCacheEnabled","quotaCacheSeconds"]
        }
    }
}

enum MessagePurpose { case interaction, progress, result, attention, quota, preview }
enum AnimationSelection { case general, idle, docked, task }

enum WindowDockModifier: String, CaseIterable {
    case option, shift, command

    static let key = "windowDockModifier"
    static var options: [(String,String)] {allCases.map {($0.rawValue,$0.title)}}

    private var title: String {
        switch self {
        case .option: return "⌥ Option"
        case .shift: return "⇧ Shift"
        case .command: return "⌘ Command"
        }
    }
    func matchesRelease(_ flags: NSEvent.ModifierFlags, lastDragModifiers: NSEvent.ModifierFlags) -> Bool {
        let supported: NSEvent.ModifierFlags = [.option,.shift,.command,.control]
        let released = flags.intersection(supported)
        let modifiers = released.isEmpty ? lastDragModifiers.intersection(supported) : released
        switch self {
        case .option: return modifiers == .option
        case .shift: return modifiers == .shift
        case .command: return modifiers == .command
        }
    }
}

enum BubbleCloseButtonPosition:String, CaseIterable {
    case upperLeft, upperRight, towardScreenCenter

    static let key = "bubbleCloseButtonPosition"
    static let title = L10n.text(.settings,"bubbleCloseButtonPosition.title")
    static let help = L10n.text(.settings,"bubbleCloseButtonPosition.help")
    static var options:[(String,String)] {
        [(upperLeft.rawValue,L10n.text(.settings,"bubbleCloseButtonPosition.option.upperLeft")),(upperRight.rawValue,L10n.text(.settings,"bubbleCloseButtonPosition.option.upperRight")),(towardScreenCenter.rawValue,L10n.text(.settings,"bubbleCloseButtonPosition.option.inward"))]
    }

    func isOnRight(windowMidX:CGFloat,screenMidX:CGFloat?,wasOnRight:Bool) -> Bool {
        switch self {
        case .upperLeft: return false
        case .upperRight: return true
        case .towardScreenCenter:
            guard let screenMidX,windowMidX != screenMidX else {return wasOnRight}
            return windowMidX < screenMidX
        }
    }
}

enum SendShortcut: String, CaseIterable {
    case commandReturn, returnToSend, controlOrCommandReturn
    var sendLabel: String {
        switch self {
        case .commandReturn:return "⌘↩"
        case .returnToSend:return "↩"
        case .controlOrCommandReturn:return L10n.text(.settings,"preferences.controlOrCommandReturn")
        }
    }
    var newlineLabel: String {self == .returnToSend ? L10n.text(.settings,"preferences.sendShortcut.text") : "↩"}
    var hint: String {L10n.format(.settings,"preferences.sendShortcut.text.2",String(describing:sendLabel),String(describing:newlineLabel))}
    static var options:[(String,String)] {allCases.map {($0.rawValue,L10n.format(.settings,"preferences.sendShortcut.text.3",String(describing:$0.sendLabel),String(describing:$0.newlineLabel)))}}
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
    static let tokenDetailsKey = "tokenDetailsExpanded"
    static let dragTiltIntensityRange = 0.0...200.0
    static let defaults: [String:Any] = [
        "approvalButtonOrder":"rejectLeft","recordHistory":true,"bubbleCardLimit":50,"recentTaskCount":5,"showTaskOverview":true,"showThinkingProgress":true,"showToolProgress":true,"hideToolFailures":true,"progressToastEnabled":true,"progressToastSeconds":2.0,"taskReminderEnabled":true,"taskReminderMinutes":5.0,
        "automaticallyCheckUpdates":false,"defaultWorkspace":"",ChatSpeed.preferenceKey:ChatSpeed.standard.rawValue,
        "taskInfoBarEnabled":true,"gitWindowEnabled":false,GitStatusStyle.key:GitStatusStyle.defaultStyle.rawValue,GitTerminology.key:false,tokenDetailsKey:false,TokenCountFormat.key:TokenCountFormat.full.rawValue,
        "bubbleMaterial":glassAvailable ? "glass" : "plain","glassFollowsSystem":true,"glassOpacity":0.5,"bubbleMotion":true,
        BubbleCloseButtonPosition.key:BubbleCloseButtonPosition.upperLeft.rawValue,
        "showDiagnostics":false,"diagnosticsPinned":true,"preloadWholeAnimation":false,"animationBufferFrames":12,"animationQuality":"512","animationFPSLimit":"full","animationOpeningCache":true,
        "animationSmoothTransition":true,"animationEdgeCleanup":true,"quotaCacheEnabled":false,"quotaCacheSeconds":60.0,
        "rememberPosition":true,"preferredDisplay":"","autoFullscreen":true,BrowserSearchEngine.key:BrowserSearchEngine.defaultEngine.rawValue,
        ProjectSendChannel.key:ProjectSendChannel.modern.rawValue,
        "ownerName":"","customAddress":"","petName":L10n.text(.settings,"identity.names.4"),
        "greetingTemplate":L10n.text(.dialogue,"dialogue.greetingTemplate"),"customLines":[String:String](),"randomWorkingLines":true,
        "taskProgressTemplate":L10n.text(.dialogue,"dialogue.taskProgressTemplate"),"taskUpdateTemplate":L10n.text(.dialogue,"dialogue.taskUpdateTemplate"),"taskSuccessTemplate":L10n.text(.dialogue,"dialogue.taskSuccessTemplate"),
        "taskFailureTemplate":L10n.text(.dialogue,"dialogue.taskFailureTemplate"),"taskInterruptedTemplate":L10n.text(.dialogue,"dialogue.taskInterruptedTemplate"),
        "quotaLoadingTemplate":L10n.text(.settings,"preferences.labels.text"),
        "taskAnswerTemplate":L10n.text(.dialogue,"dialogue.taskAnswerTemplate"),"taskApprovalTemplate":L10n.text(.dialogue,"dialogue.taskApprovalTemplate"),
        "dragTiltEnabled":true,"dragTiltIntensity":100.0,"sideDockEnabled":true,"sideExposurePercent":55.0,"notchDockEnabled":true,"notchExposurePercent":55.0,
        "windowDockEnabled":false,WindowDockModifier.key:WindowDockModifier.option.rawValue,
        "leisureInterval":15.0,"autoMove":true,"movementRange":"screen","avoidRepeat":true,"playbackSpeed":1.0,
        "animationWeights":[String:Int](),"animationSpeeds":[String:Double](),"taskOpening":true,"taskCelebration":true,
        "sendShortcut":"commandReturn","taskBubbles":true,"progressBubbles":true,"resultBubbles":true,"interactionBubbles":true,
        "interactionSeconds":5.0,"progressSeconds":10.0,"resultSeconds":20.0,"quotaSeconds":5.0,
        "autoReadTime":true,"pauseOnHover":true,"countAfterReveal":true,"typingEffect":true,"soundEnabled":true,
        "quietCompanion":false,"quietSchedule":false,"quietStart":22*60,"quietEnd":8*60,
        "petPercent":100,"petShadow":false,"bubblePercent":100,"bubbleAspectEnabled":false,"bubbleAspectRatio":1.5,"messageFontSize":13.0,"appearanceMode":"system","accentStyle":"system","accentRGB":[149.0/255,61.0/255,150.0/255]
    ].merging(PetGestureSetting.all.map {($0.key,$0.defaultAction)}) {_, gesture in gesture}
     .merging(ConversationLines.defaults) {existing,_ in existing}
    static let ranges: [String:ClosedRange<Double>] = [
        "dragTiltIntensity":dragTiltIntensityRange,
        "taskReminderMinutes":1...30,"bubbleCardLimit":5...100,"recentTaskCount":1...20,
        "sideExposurePercent":40...85,"notchExposurePercent":40...85,"glassOpacity":0...1,"animationBufferFrames":6...240,"leisureInterval":5...180,"playbackSpeed":0.75...1.5,"interactionSeconds":0...60,"progressSeconds":0...60,"progressToastSeconds":1...10,
        "resultSeconds":0...120,"quotaSeconds":0...120,"quotaCacheSeconds":15...300,"quietStart":0...1439,"quietEnd":0...1439,
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
        return L10n.text(.settings,"preferences.petPreferences.text.2")
        #else
        return L10n.text(.settings,"preferences.petPreferences.text.3")
        #endif
    }
    var usesGlass: Bool {Self.glassAvailable && string("bubbleMaterial") == "glass"}
    private(set) var desktopVersion:CodexConnection.DesktopVersion?
    private var automaticChannel:ProjectSendChannel = .modern
    var projectChannelHint:String {
        let current = desktopVersion.map {L10n.text(.settings,"preferences.petPreferences.text.4")+$0.display} ?? L10n.text(.settings,"preferences.petPreferences.text.5")
        return current+L10n.text(.settings,"preferences.petPreferences.text.6")+automaticChannel.title+"」。"
    }
    func refreshDesktopVersion() {
        let version = CodexConnection.detectDesktopVersion()
        guard version != desktopVersion else {return}
        desktopVersion = version
        automaticChannel = ProjectSendChannel.recommended(for:version?.number)
        notify([ProjectSendChannel.key])
    }
    var projectSendChannel:ProjectSendChannel {ProjectSendChannel(rawValue:string(ProjectSendChannel.key)) ?? .modern}
    static let choices = ["approvalButtonOrder":["rejectLeft","allowLeft"],"bubbleMaterial":["glass","plain"],"animationQuality":["auto","720","512","384","256"],"animationFPSLimit":["full","20","15"],"sendShortcut":SendShortcut.allCases.map(\.rawValue),"movementRange":["still","nearby","screen"],
        "appearanceMode":AppAppearance.choices.map(\.0),"accentStyle":AppAccent.choices.map(\.0),
        TokenCountFormat.key:TokenCountFormat.allCases.map(\.rawValue),GitStatusStyle.key:GitStatusStyle.allCases.map(\.rawValue),BrowserSearchEngine.key:BrowserSearchEngine.allCases.map(\.rawValue),
        ChatSpeed.preferenceKey:ChatSpeed.allCases.map(\.rawValue),ProjectSendChannel.key:ProjectSendChannel.allCases.map(\.rawValue),BubbleCloseButtonPosition.key:BubbleCloseButtonPosition.allCases.map(\.rawValue),WindowDockModifier.key:WindowDockModifier.allCases.map(\.rawValue)]
        .merging(PetGestureSetting.all.map {($0.key,PetGestureSetting.actions.map(\.0))}) {_, gesture in gesture}
    private(set) var compatibilityNotice:String?
    let defaults: UserDefaults
    init(defaults: UserDefaults = SettingsStorage.defaults) {
        self.defaults = defaults
        desktopVersion = CodexConnection.detectDesktopVersion()
        automaticChannel = ProjectSendChannel.recommended(for:desktopVersion?.number)
        guard defaults.integer(forKey:SettingsStorage.schemaKey) <= SettingsStorage.schemaVersion else {return}
        if let legacy = defaults.object(forKey:"petChatFastMode") as? Bool {
            if defaults.object(forKey:ChatSpeed.preferenceKey) == nil {
                defaults.set((legacy ? ChatSpeed.fast : .standard).rawValue,forKey:ChatSpeed.preferenceKey)
            }
            defaults.removeObject(forKey:"petChatFastMode")
        }
        TemplateSyntax.migrateOnce(defaults,keys:SettingsSection.identity.keys.filter {TemplateSyntax.isTemplateKey($0) || $0 == "customLines"})
        let receivedKeys = ["desktopTaskReceivedTemplate","desktopTaskReceivedBodyTemplate"]
        let received = Dictionary(uniqueKeysWithValues:receivedKeys.compactMap {key in defaults.object(forKey:key).map {(key,$0)}})
        for (key,value) in ConversationLines.migrateReceivedLine(received) {defaults.set(value,forKey:key)}
        defaults.removeObject(forKey:"desktopTaskReceivedBodyTemplate")
        defaults.removeObject(forKey:"addressMode")
        defaults.removeObject(forKey:"showOnLaunch")
        defaults.removeObject(forKey:"gitWindowPinned")
        defaults.removeObject(forKey:"gitWindowSeconds")
        if let oldFavorites = defaults.stringArray(forKey:"favorites") {
            let weights = defaults.dictionary(forKey:"animationWeights") as? [String:Int] ?? [:]
            defaults.set(Self.combinedAnimationWeights(weights,favorites:oldFavorites),forKey:"animationWeights")
        }
        defaults.removeObject(forKey:"favorites")

        if let old = defaults.string(forKey:"animationFPSLimit"), ["24","30"].contains(old) {defaults.set("full",forKey:"animationFPSLimit")}
    }
    func validatePlayback() throws {
        guard defaults.integer(forKey:SettingsStorage.schemaKey) <= SettingsStorage.schemaVersion else {
            throw PetFailure(message:L10n.text(.settings,"preferences.validatePlayback.message"))
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
            compatibilityNotice = L10n.text(.settings,"preferences.validatePlayback.text")
        }
    }

    static func displayID(_ screen: NSScreen) -> String {(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""}
    func value(_ key: String) -> Any {
        if let saved = defaults.object(forKey:key) {return saved}
        if key == ProjectSendChannel.key {return automaticChannel.rawValue}
        return Self.defaults[key]!
    }
    func bool(_ key: String) -> Bool {value(key) as? Bool ?? false}
    func number(_ key: String) -> Double {(value(key) as? NSNumber)?.doubleValue ?? 0}
    func string(_ key: String) -> String {value(key) as? String ?? ""}
    var tokenCountFormat:TokenCountFormat {TokenCountFormat(rawValue:string(TokenCountFormat.key)) ?? .full}
    var gitStatusStyle:GitStatusStyle {GitStatusStyle(rawValue:string(GitStatusStyle.key)) ?? .defaultStyle}
    var gitTerminology:GitTerminology {bool(GitTerminology.key) ? .english : .localized}
    var bubbleCloseButtonPosition:BubbleCloseButtonPosition {BubbleCloseButtonPosition(rawValue:string(BubbleCloseButtonPosition.key)) ?? .upperLeft}
    var animationBufferFrames: Int { Int(number("animationBufferFrames")) }
    var defaultWorkspace:URL {
        let path = string("defaultWorkspace")
        return path.isEmpty ? LocalStorage.workspace : URL(fileURLWithPath:path,isDirectory:true).standardizedFileURL
    }
    var usesAutomaticAnimationResolution: Bool { string("animationQuality") == "auto" }
    func animationResolution(points: Double, backingScale: Double) -> Int {
        if !usesAutomaticAnimationResolution { return Int(string("animationQuality"))! }
        let pixels = points * backingScale
        return [256,384,512,720].first { Double($0) >= pixels } ?? 720
    }
    func animationFPS(native: Double) -> Double { string("animationFPSLimit") == "full" ? native : min(native,Double(string("animationFPSLimit"))!) }
    var sendShortcut: SendShortcut {SendShortcut(rawValue:string("sendShortcut")) ?? .commandReturn}
    func set(_ value: Any, for key: String,from sender:AnyObject? = nil) {
        defaults.set(TemplateSyntax.migrate([key:value])[key]!,forKey:key); notify([key],from:sender)
    }
    private func notify(_ keys: [String],from sender:AnyObject? = nil) {
        var info:[String:Any] = ["keys":keys]
        info["sender"] = sender
        NotificationCenter.default.post(name:Self.didChange,object:self,userInfo:info)
    }
    func reset(_ keys: [String]) {for key in keys {defaults.removeObject(forKey:key)}; notify(keys)}
    var petName: String {let s = string("petName").trimmingCharacters(in:.whitespacesAndNewlines); return s.isEmpty ? L10n.text(.settings,"identity.names.4") : s}
    // 产品身份固定；petName 只用于角色称呼和互动文案。
    static let productName = L10n.text(.settings,"preferences.productName")
    var appName: String {Self.productName}
    var ownerName:String {
        let name = string("ownerName").trimmingCharacters(in:.whitespacesAndNewlines)
        return name.isEmpty ? L10n.text(.settings,"preferences.reset.text") : name
    }
    // 模板自行选择变量；特定称呼留空沿用用户名。
    var address: String {
        let custom = string("customAddress").trimmingCharacters(in:.whitespacesAndNewlines)
        if custom.isEmpty {return ownerName}
        return TemplateSyntax.render(custom,values:[TemplateSyntax.petName:petName,TemplateSyntax.userName:ownerName])
    }
    func template(_ text: String) -> String {
        TemplateSyntax.render(text,values:[TemplateSyntax.customAddress:address,TemplateSyntax.petName:petName,TemplateSyntax.userName:ownerName])
    }
    func statusLine(_ key:String) -> String {
        let value = string(key)
        return template(value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? Self.defaults[key] as? String ?? "" : value)
    }
    func workingOverviewLine() -> String {
        let key = bool("randomWorkingLines") ? ConversationLines.working.randomElement()!.key : "taskProgressTemplate"
        return statusLine(key)
    }
    var sensitiveQuestionNotice: String {template(L10n.text(.conversation,"preferences.sensitiveQuestionNotice"))}
    var sensitiveInputNotice: String {template(L10n.text(.conversation,"preferences.sensitiveInputNotice"))}
    func taskResultLine(_ status:String) -> String {
        statusLine(status == "completed" ? "taskSuccessTemplate" : TaskOutcome.stoppedStatuses.contains(status) ? "taskInterruptedTemplate" : "taskFailureTemplate")
    }
    // 只传入应用自带文案，不对用户消息、模型正文或历史记录做全局替换。
    func templateSource(_ text:String) -> String {text.replacingOccurrences(of:"白龙娘",with:TemplateSyntax.petName).replacingOccurrences(of:"白龙",with:TemplateSyntax.petName).replacingOccurrences(of:"主人",with:TemplateSyntax.userName)}
    func fixedText(_ text: String) -> String {template(templateSource(text))}
    func line(for clip: Clip) -> String? {
        if let custom = (value("customLines") as? [String:String])?[clip.id], !custom.isEmpty {return template(custom)}
        return clip.localizedLine.map(fixedText)
    }
    func setLine(_ text: String, for id: String) {
        var lines = value("customLines") as? [String:String] ?? [:]
        if text.isEmpty {lines.removeValue(forKey:id)} else {lines[id] = text}
        set(lines,for:"customLines")
    }
    static let clipSpeedOptions:[Double] = [0.75,1,1.25,1.5]
    static func clipWeightRange(_ id:String) -> ClosedRange<Int> {(id == "idle" ? 1 : 0)...12}
    private static func defaultAnimationWeight(_ id:String) -> Int {id == "idle" ? 4 : id == "idle2" ? 1 : 3}
    private static func combinedAnimationWeights(_ weights:[String:Int],favorites:[String]) -> [String:Int] {
        var weights = weights
        for id in Set(favorites) {weights[id] = (weights[id] ?? defaultAnimationWeight(id))*2}
        return weights
    }
    func defaultWeight(_ id:String) -> Int {Self.defaultAnimationWeight(id)}
    func baseWeight(_ id: String) -> Int {
        (value("animationWeights") as? [String:Int])?[id] ?? defaultWeight(id)
    }
    func weight(_ id:String) -> Double {Double(baseWeight(id))}
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
        var values = Dictionary(uniqueKeysWithValues:Self.defaults.keys.map {($0,value($0))})
        // 缺少手动覆盖时，导入方也按自己的桌面端版本选择。
        values[ProjectSendChannel.key] = defaults.object(forKey:ProjectSendChannel.key)
        return try JSONSerialization.data(withJSONObject:["schemaVersion":SettingsStorage.schemaVersion,"settings":values],options:[.prettyPrinted,.sortedKeys])
    }
    func importData(_ data: Data, clipIDs: Set<String>) throws {
        guard let document = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let schema = document["schemaVersion"] as? Int,var values = document["settings"] as? [String:Any] else {
            throw PetFailure(message:L10n.text(.settings,"preferences.importData.message"))
        }
        guard (1...SettingsStorage.schemaVersion).contains(schema) else {
            throw PetFailure(message:L10n.format(.settings,"preferences.importData.message.2",String(describing:schema)))
        }
        if let legacy = values.removeValue(forKey:"petChatFastMode") {
            guard Self.valid(legacy,key:"petChatFastMode",baseline:false,clipIDs:clipIDs) else {
                throw PetFailure(message:L10n.format(.settings,"preferences.importData.message.5","petChatFastMode"))
            }
            if values[ChatSpeed.preferenceKey] == nil {
                values[ChatSpeed.preferenceKey] = ((legacy as! Bool) ? ChatSpeed.fast : .standard).rawValue
            }
        }
        values = TemplateSyntax.migrate(values)
        values = ConversationLines.migrateReceivedLine(values)
        // 旧短进展标题已由共用进展取代。导入时跳过旧字段，本机旧版保存的值保留。
        for key in ["taskThinkingTemplate","taskToolTemplate","taskCommandTemplate","taskCommandCompletedTemplate","taskWarningTemplate"] {
            values.removeValue(forKey:key)
        }
        values.removeValue(forKey:"addressMode")
        values.removeValue(forKey:"showOnLaunch")
        values.removeValue(forKey:"gitWindowPinned")
        values.removeValue(forKey:"gitWindowSeconds")
        if let favorites = values.removeValue(forKey:"favorites") {
            guard Self.valid(favorites,key:"favorites",baseline:[String](),clipIDs:clipIDs) else {throw PetFailure(message:L10n.text(.settings,"preferences.importData.message.3"))}
            let rawWeights = values["animationWeights"] ?? [String:Int]()
            guard Self.valid(rawWeights,key:"animationWeights",baseline:[String:Int](),clipIDs:clipIDs),let weights = rawWeights as? [String:Int] else {throw PetFailure(message:L10n.text(.settings,"preferences.importData.message.4"))}
            values["animationWeights"] = Self.combinedAnimationWeights(weights,favorites:favorites as! [String])
        }

        if let old = values["animationFPSLimit"] as? String, ["24","30"].contains(old) {values["animationFPSLimit"] = "full"}
        for (key,value) in values {
            // dev.7 / dev.8 导出包含旧开关；统一流式后只校验类型，不恢复旧播放策略。
            if key == "lowResourceMode", let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { continue }
            guard let baseline = Self.defaults[key], Self.valid(value,key:key,baseline:baseline,clipIDs:clipIDs) else {
                throw PetFailure(message:L10n.format(.settings,"preferences.importData.message.5",String(describing:key)))
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
            return map.allSatisfy { id,number in
                guard let weight = Int(exactly:number.doubleValue) else {return false}
                return clipIDs.contains(id) && CFGetTypeID(number) != CFBooleanGetTypeID() && clipWeightRange(id).contains(weight)
            }
        }
        if key == "animationSpeeds", let map = value as? [String:NSNumber] {return map.allSatisfy {clipIDs.contains($0.key) && CFGetTypeID($0.value) != CFBooleanGetTypeID() && clipSpeedOptions.contains($0.value.doubleValue)}}
        if key == "customLines", let map = value as? [String:String] {return map.allSatisfy {clipIDs.contains($0.key) && TemplateSyntax.count($0.value) <= 120}}
        if key == "favorites", let list = value as? [String] {return list.allSatisfy {clipIDs.contains($0)}}
        if key == "accentRGB", let rgb = value as? [NSNumber] {return rgb.count == 3 && rgb.allSatisfy {CFGetTypeID($0) != CFBooleanGetTypeID() && (0...1).contains($0.doubleValue)}}
        if let range = ranges[key], let n = value as? NSNumber {
            let integer = ["bubbleCardLimit","recentTaskCount","petPercent","bubblePercent","quietStart","quietEnd","animationBufferFrames","quotaCacheSeconds","dragTiltIntensity"].contains(key)
            return CFGetTypeID(n) != CFBooleanGetTypeID() && range.contains(n.doubleValue) && (!integer || n.doubleValue.rounded() == n.doubleValue)
        }
        if let b = baseline as? NSNumber, CFGetTypeID(b) == CFBooleanGetTypeID() {return (value as? NSNumber).map {CFGetTypeID($0) == CFBooleanGetTypeID()} ?? false}
        if baseline is String, let s = value as? String {return (TemplateSyntax.isTemplateKey(key) ? TemplateSyntax.count(s) : s.count) <= (key.hasSuffix("Template") ? ConversationLines.limit(key) : ["ownerName","customAddress","petName"].contains(key) ? 20 : 80) && (choices[key]?.contains(s) ?? true)}
        return false
    }
}
