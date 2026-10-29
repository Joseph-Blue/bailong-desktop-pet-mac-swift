import AppKit
import ServiceManagement
import UniformTypeIdentifiers

private final class SettingsAction: NSObject {
    let body: (NSControl) -> Void
    init(_ body: @escaping (NSControl) -> Void) {self.body = body}
    @objc func invoke(_ sender: NSControl) {body(sender)}
}

private final class SettingsGroupView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect:bounds,xRadius:10,yRadius:10).fill()
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); needsDisplay = true}
}

final class SettingsPanel: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:680),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
    let preferences: PetPreferences
    let catalog: Catalog?
    private let sidebar = NSTableView(), scroll = NSScrollView(), content = NSStackView()
    private let resetButton = ActionButton("恢复本页设置为默认值") {}
    private var actions = [SettingsAction]()
    private var textActions = [ObjectIdentifier:(String)->Void]()
    private var identityPreview: NSTextField?
    private var selected: SettingsSection = .general
    private var hasShown = false
    var onClose: () -> Void = {}
    var onPreview: (Clip) -> Void = { _ in }
    var onMessagePreview: (MessagePurpose) -> Void = { _ in }
    init(preferences: PetPreferences = .shared, catalog: Catalog? = nil) {
        self.preferences = preferences; self.catalog = catalog
        super.init()
        window.title = "设置"; window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width:840,height:560); window.setFrameAutosaveName("BailongSettingsWindow")
        let root = NSView(); window.contentView = root
        let side = NSVisualEffectView(); side.material = .sidebar; side.blendingMode = .behindWindow
        let sideScroll = NSScrollView(); sideScroll.drawsBackground = false; sideScroll.hasVerticalScroller = false
        let column = NSTableColumn(identifier:NSUserInterfaceItemIdentifier("section")); sidebar.addTableColumn(column)
        sidebar.headerView = nil; sidebar.style = .sourceList; sidebar.rowHeight = 38; sidebar.backgroundColor = .clear
        sidebar.dataSource = self; sidebar.delegate = self; sidebar.allowsEmptySelection = false
        sidebar.setAccessibilityLabel("设置分类"); sideScroll.documentView = sidebar
        side.addSubview(sideScroll)
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let document = TopDownView(); scroll.documentView = document
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 18
        document.addSubview(content)
        let footer = NSView(), hint = label("更改会自动保存"); hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize:11)
        footer.addSubview(hint); footer.addSubview(resetButton)
        resetButton.callback = { [weak self] in self?.restorePage() }
        for view in [side,scroll,footer] {root.addSubview(view)}
        for view in [side,sideScroll,scroll,document,content,footer,hint,resetButton] {view.translatesAutoresizingMaskIntoConstraints = false}
        NSLayoutConstraint.activate([
            side.leadingAnchor.constraint(equalTo:root.leadingAnchor),side.topAnchor.constraint(equalTo:root.topAnchor),side.bottomAnchor.constraint(equalTo:root.bottomAnchor),side.widthAnchor.constraint(equalToConstant:174),
            sideScroll.leadingAnchor.constraint(equalTo:side.leadingAnchor,constant:8),sideScroll.trailingAnchor.constraint(equalTo:side.trailingAnchor,constant:-8),sideScroll.topAnchor.constraint(equalTo:side.topAnchor,constant:16),sideScroll.bottomAnchor.constraint(equalTo:side.bottomAnchor,constant:-16),
            scroll.leadingAnchor.constraint(equalTo:side.trailingAnchor),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor),scroll.topAnchor.constraint(equalTo:root.topAnchor),scroll.bottomAnchor.constraint(equalTo:footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo:side.trailingAnchor),footer.trailingAnchor.constraint(equalTo:root.trailingAnchor),footer.bottomAnchor.constraint(equalTo:root.bottomAnchor),footer.heightAnchor.constraint(equalToConstant:54),
            hint.leadingAnchor.constraint(equalTo:footer.leadingAnchor,constant:24),hint.centerYAnchor.constraint(equalTo:footer.centerYAnchor),resetButton.trailingAnchor.constraint(equalTo:footer.trailingAnchor,constant:-24),resetButton.centerYAnchor.constraint(equalTo:footer.centerYAnchor),
            document.leadingAnchor.constraint(equalTo:scroll.contentView.leadingAnchor),document.topAnchor.constraint(equalTo:scroll.contentView.topAnchor),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),content.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:24),content.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-24),content.topAnchor.constraint(equalTo:document.topAnchor,constant:24),content.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-24)
        ])
        sidebar.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAccent),name:AppAccent.didChange,object:nil)
        render()
    }
    func show(section: SettingsSection? = nil) {
        if let section {select(section)} else {render()}
        if !hasShown {window.center(); hasShown = true}
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func select(_ section: SettingsSection) {selected = section; sidebar.selectRowIndexes(IndexSet(integer:section.rawValue),byExtendingSelection:false); render()}
    func numberOfRows(in tableView: NSTableView) -> Int {SettingsSection.allCases.count}
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = SettingsSection(rawValue:row)!, view = NSTableCellView()
        let icon = NSImageView(), text = NSTextField(labelWithString:section.title)
        icon.image = NSImage(systemSymbolName:section.symbol,accessibilityDescription:nil); icon.contentTintColor = AppAccent.color
        text.font = .systemFont(ofSize:13); view.addSubview(icon); view.addSubview(text); view.textField = text; view.imageView = icon
        icon.translatesAutoresizingMaskIntoConstraints = false; text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:8),icon.centerYAnchor.constraint(equalTo:view.centerYAnchor),icon.widthAnchor.constraint(equalToConstant:20),icon.heightAnchor.constraint(equalToConstant:20),text.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:8),text.centerYAnchor.constraint(equalTo:view.centerYAnchor),text.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-4)])
        return view
    }
    func tableViewSelectionDidChange(_ notification: Notification) {if let section = SettingsSection(rawValue:sidebar.selectedRow) {selected = section; render()}}
    func windowWillClose(_ notification: Notification) {window.makeFirstResponder(nil); onClose()}
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {return}
        textActions[ObjectIdentifier(field)]?(field.stringValue)
        identityPreview?.stringValue = preferences.template(preferences.string("greetingTemplate"))
    }
    private func attach(_ control: NSControl, _ callback: @escaping (NSControl)->Void) {
        let action = SettingsAction(callback); actions.append(action); control.target = action; control.action = #selector(SettingsAction.invoke(_:))
    }
    private func fill(_ view: NSView, in stack: NSStackView) {view.translatesAutoresizingMaskIntoConstraints = false; stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
    private func group(_ title: String, _ rows: [NSView]) {
        let heading = label(title,bold:true); fill(heading,in:content)
        let box = SettingsGroupView()
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        box.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:box.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:box.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:box.topAnchor,constant:12),stack.bottomAnchor.constraint(equalTo:box.bottomAnchor,constant:-12)])
        for (index,row) in rows.enumerated() {
            if index > 0 {let line = NSBox(); line.boxType = .separator; fill(line,in:stack)}
            fill(row,in:stack)
        }
        fill(box,in:content)
    }
    private func row(_ title: String, detail: String? = nil, control: NSView) -> NSView {
        let texts = NSStackView(); texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 4
        fill(label(title),in:texts)
        if let detail {let explanation = label(detail); explanation.font = .systemFont(ofSize:11); explanation.textColor = .secondaryLabelColor; fill(explanation,in:texts)}
        return alignedRow(leading:texts,control:control)
    }
    private func alignedRow(leading: NSView, control: NSView) -> NSView {
        // 显式固定左右两端；多余宽度留给左侧说明，不拉长开关或按钮。
        let row = NSView()
        for view in [leading,control] {view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view)}
        leading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        control.setContentHuggingPriority(.required,for:.horizontal)
        control.setContentCompressionResistancePriority(.required,for:.horizontal)
        let compactHeight = row.heightAnchor.constraint(equalToConstant:32); compactHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo:row.leadingAnchor),
            leading.trailingAnchor.constraint(equalTo:control.leadingAnchor,constant:-24),
            leading.centerYAnchor.constraint(equalTo:row.centerYAnchor),
            leading.topAnchor.constraint(greaterThanOrEqualTo:row.topAnchor),
            leading.bottomAnchor.constraint(lessThanOrEqualTo:row.bottomAnchor),
            control.trailingAnchor.constraint(equalTo:row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo:row.centerYAnchor),
            control.topAnchor.constraint(greaterThanOrEqualTo:row.topAnchor),
            control.bottomAnchor.constraint(lessThanOrEqualTo:row.bottomAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant:32),compactHeight
        ])
        return row
    }
    private func toggle(_ title: String, _ key: String, detail: String? = nil) -> NSView {
        let control = NSSwitch(); control.state = preferences.bool(key) ? .on : .off; control.setAccessibilityLabel(title)
        attach(control) { [weak self] sender in self?.preferences.set((sender as! NSSwitch).state == .on,for:key) }
        return row(title,detail:detail,control:control)
    }
    private func popup(_ title: String, options: [(String,String)], value: String, width: CGFloat = 190, identifier: String? = nil, changed: @escaping (String)->Void) -> NSView {
        let menu = NSPopUpButton(); menu.addItems(withTitles:options.map(\.1)); menu.selectItem(at:options.firstIndex {$0.0 == value} ?? 0)
        if let identifier {menu.identifier = NSUserInterfaceItemIdentifier(identifier)}
        menu.widthAnchor.constraint(equalToConstant:width).isActive = true; menu.setAccessibilityLabel(title)
        attach(menu) {sender in let index = (sender as! NSPopUpButton).indexOfSelectedItem; if options.indices.contains(index) {changed(options[index].0)}}
        return row(title,control:menu)
    }
    private func choice(_ title: String, _ key: String, _ options: [(String,String)]) -> NSView {
        popup(title,options:options,value:preferences.string(key),width:key == "sendShortcut" ? 260 : 190,identifier:key) { [weak self] value in
            self?.preferences.set(value,for:key)
            self?.identityPreview?.stringValue = self?.preferences.template(self?.preferences.string("greetingTemplate") ?? "") ?? ""
        }
    }
    @objc private func refreshAccent() {
        func update(_ view: NSView) {
            if let slider = view as? NSSlider {slider.trackFillColor = AppAccent.color}
            if let well = view as? NSColorWell {well.color = AppAccent.color}
            if let menu = view as? NSPopUpButton, menu.identifier?.rawValue == "accentStyle" {menu.selectItem(at:AppAccent.choices.firstIndex {$0.0 == preferences.string("accentStyle")} ?? 0)}
            for child in view.subviews {update(child)}
        }
        if let root = window.contentView {update(root)}
        sidebar.enumerateAvailableRowViews { [weak self] _, index in
            (self?.sidebar.view(atColumn:0,row:index,makeIfNecessary:false) as? NSTableCellView)?.imageView?.contentTintColor = AppAccent.color
        }
    }
    private func entry(_ title: String, value: String, placeholder: String = "", limit: Int = 80, changed: @escaping (String)->Void) -> NSView {
        let field = NSTextField(string:value); field.placeholderString = placeholder; field.delegate = self
        field.widthAnchor.constraint(equalToConstant:240).isActive = true; field.setAccessibilityLabel(title)
        textActions[ObjectIdentifier(field)] = {text in let bounded = String(text.prefix(limit)); if bounded != text {field.stringValue = bounded}; changed(bounded)}
        return row(title,control:field)
    }
    private func text(_ title: String, _ key: String, placeholder: String = "", limit: Int = 80) -> NSView {
        entry(title,value:preferences.string(key),placeholder:placeholder,limit:limit) { [weak self] value in self?.preferences.set(value,for:key) }
    }
    private func slider(_ title: String, _ key: String, range: ClosedRange<Double>, step: Double = 1, suffix: String, detail: String? = nil) -> NSView {
        let slider = NSSlider(value:preferences.number(key),minValue:range.lowerBound,maxValue:range.upperBound,target:nil,action:nil)
        slider.isContinuous = true; slider.trackFillColor = AppAccent.color; slider.widthAnchor.constraint(equalToConstant:132).isActive = true
        if key == "petPercent" || key == "bubblePercent" {slider.numberOfTickMarks = Int((range.upperBound-range.lowerBound)/25)+1; slider.tickMarkPosition = .below}
        slider.setAccessibilityLabel(title)
        let number = NSTextField(string:""); number.alignment = .right; number.widthAnchor.constraint(equalToConstant:54).isActive = true; number.setAccessibilityLabel(title+suffix); (number.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        let formatter = NumberFormatter(); formatter.minimum = NSNumber(value:range.lowerBound); formatter.maximum = NSNumber(value:range.upperBound); formatter.maximumFractionDigits = step < 1 ? 2 : 0; formatter.usesGroupingSeparator = false; number.formatter = formatter
        func format(_ value: Double) {number.doubleValue = value}
        format(slider.doubleValue)
        attach(slider) { [weak self] sender in
            let value = ((sender.doubleValue/step).rounded()*step); format(value); self?.preferences.set(value,for:key)
        }
        attach(number) { [weak self] sender in let value = max(range.lowerBound,min(range.upperBound,(sender.doubleValue/step).rounded()*step)); slider.doubleValue = value; format(value); self?.preferences.set(value,for:key) }
        let unit = label(suffix); unit.font = .systemFont(ofSize:11); unit.textColor = .secondaryLabelColor
        let controls = NSStackView(views:[slider,number,unit]); controls.spacing = 6
        return row(title,detail:detail,control:controls)
    }
    private func time(_ title: String, _ key: String) -> NSView {
        let picker = NSDatePicker(); picker.datePickerStyle = .textFieldAndStepper; picker.datePickerElements = [.hourMinute]; picker.locale = Locale(identifier:"zh_CN")
        let minutes = Int(preferences.number(key)); picker.dateValue = Calendar.current.date(from:DateComponents(year:2026,month:1,day:1,hour:minutes/60,minute:minutes%60))!
        picker.setAccessibilityLabel(title)
        attach(picker) { [weak self] sender in let c = Calendar.current.dateComponents([.hour,.minute],from:(sender as! NSDatePicker).dateValue); self?.preferences.set((c.hour ?? 0)*60+(c.minute ?? 0),for:key) }
        return row(title,control:picker)
    }
    private func render() {
        guard window.contentView != nil else {return}
        for view in content.arrangedSubviews {content.removeArrangedSubview(view); view.removeFromSuperview()}
        actions.removeAll(); textActions.removeAll(); identityPreview = nil
        let heading = label(selected.title,bold:true); heading.font = .systemFont(ofSize:24,weight:.bold); fill(heading,in:content)
        resetButton.isHidden = selected == .advanced
        switch selected {
        case .general: general()
        case .identity: identity()
        case .activity: activity()
        case .messages: messages()
        case .appearance: appearance()
        case .advanced: advanced()
        }
        scroll.contentView.scroll(to:.zero)
    }
    private func general() {
        let login = SMAppService.mainApp.status
        let loginText = login == .enabled ? "已启用" : login == .requiresApproval ? "等待系统批准" : "未启用"
        group("启动",[
            row("登录时启动",detail:loginText,control:ActionButton(login == .enabled ? "停用…" : login == .requiresApproval ? "打开登录项…" : "启用…") { [weak self] in self?.configureLogin() }),
            row("随 Codex 启动",detail:FileManager.default.fileExists(atPath:FollowLauncher.plist.path) ? "已启用跟随启动" : "打开 Codex 或 ChatGPT 时启动桌宠",control:ActionButton("配置…") { [weak self] in FollowLauncher.configure(); self?.render() }),
            toggle("启动后显示桌宠","showOnLaunch"),toggle("记住上次位置","rememberPosition")])
        var displays = [("","跟随当前屏幕")] + NSScreen.screens.map {(PetPreferences.displayID($0),$0.localizedName)}
        let saved = preferences.string("preferredDisplay")
        if !displays.contains(where:{$0.0 == saved}) {displays.append((saved,"已断开的显示器（暂用当前屏幕）"))}
        group("桌面",[toggle("全屏时自动隐藏","autoFullscreen"),choice("所在显示器","preferredDisplay",displays)])
    }
    private func configureLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {showError("请从应用包设置登录启动",PetFailure(message:"开发脚本不会注册登录项。请使用构建后的 .app。")); return}
        do {
            switch SMAppService.mainApp.status {
            case .enabled: try SMAppService.mainApp.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try SMAppService.mainApp.register()
            }
            render()
        } catch {showError("登录启动设置失败",error)}
    }
    private func identity() {
        group("我们怎么称呼彼此",[text("你的名字","ownerName",placeholder:"例如：阿哲"),choice("怎么称呼你","addressMode",[("master","主人"),("name","你的名字"),("custom","自定义称呼")]),text("自定义称呼","customAddress",placeholder:"例如：阿哲主人"),text("桌宠的名字","petName",placeholder:"白龙娘")])
        let preview = label(preferences.template(preferences.string("greetingTemplate"))); preview.font = .systemFont(ofSize:15,weight:.medium); identityPreview = preview
        group("见面时说",[text("问候语","greetingTemplate",limit:500),label("可使用 {称呼}、{名字}、{桌宠}。称呼会用于新的固定台词与内置会话，原始对话正文保持不变。"),alignedRow(leading:preview,control:ActionButton("预览消息") { [weak self] in self?.onMessagePreview(.preview) })])
        if let catalog {
            let lines = (catalog.variants+catalog.work).filter {$0.line != nil}
            group("互动台词",lines.map {clip in entry(clip.title,value:(preferences.value("customLines") as? [String:String])?[clip.id] ?? "",placeholder:clip.line ?? "",limit:500) { [weak self] in self?.preferences.setLine($0,for:clip.id) }})
        }
    }
    private func activity() {
        let actions = [("none","无动作"),("chat","临时聊天面板"),("quota","查看额度"),("history","查看历史消息"),("random","随机动画")]
        group("鼠标互动",[choice("单击桌宠","singleClickAction",actions),choice("双击桌宠","doubleClickAction",actions),choice("右键双击桌宠","rightDoubleClickAction",actions),label("普通状态单击松手立即执行，双击的第一下会先执行单击动作。躲在角落时，单击松手后等待 250 毫秒再召回，不执行单击动作；期间第二击取消召回并执行双击动作。拖动立即召回。右键按下立即打开菜单，双击时关闭菜单并执行所选动作。")])
        let interval = preferences.number("leisureInterval")
        let preset = interval == 60 ? "60" : interval == 15 ? "15" : interval == 8 ? "8" : "custom"
        group("自主活动",[
            popup("活跃程度",options:[("60","安静"),("15","适中"),("8","活泼"),("custom","自定义")],value:preset) { [weak self] value in if let seconds = Double(value) {self?.preferences.set(seconds,for:"leisureInterval"); self?.render()} },
            slider("活动间隔","leisureInterval",range:5...180,suffix:"秒",detail:"到达间隔后，当前动作播放完再切换。"),
            toggle("自主移动","autoMove"),choice("活动范围","movementRange",[("still","原地陪伴"),("nearby","小范围活动"),("screen","整个屏幕")]),toggle("减少重复动作","avoidRepeat"),
            slider("整体播放速度","playbackSpeed",range:0.75...1.5,step:0.05,suffix:"×",detail:"动作和位移使用同一时间轴。单个动作倍率会与整体倍率相乘。")])
        group("任务动作",[toggle("收到任务时播放开场","taskOpening"),toggle("完成任务时播放庆祝","taskCelebration")])
        guard let catalog else {return}
        for (title,clips,automatic) in [("待机动作",catalog.idles+catalog.extras,true),("互动动作",catalog.variants,true),("工作动作",catalog.work,true),("移动动作",catalog.movementAnimations,true),("鼠标与额度动作",[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation],false)] {
            group(title,clips.map {clip in animationRow(clip,automatic:automatic)})
        }
        fill(label("频率控制同组随机选择的偏好；星标会让该动作更常出现。手动预览和明确的拖拽、落地、额度及任务事件不受随机频率影响。默认待机始终保留。"),in:content)
    }
    private func animationRow(_ clip: Clip, automatic: Bool) -> NSView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let controls = NSStackView(); controls.spacing = 8
        let preview = ActionButton("播放") { [weak self] in self?.onPreview(clip) }; preview.image = NSImage(systemSymbolName:"play.fill",accessibilityDescription:nil); preview.imagePosition = .imageLeading
        if automatic {
            let star = NSButton(checkboxWithTitle:"偏爱",target:nil,action:nil); star.state = preferences.favorites.contains(clip.id) ? .on : .off
            attach(star) { [weak self] sender in guard let self else {return}; var values = self.preferences.favorites.filter {$0 != clip.id}; if (sender as! NSButton).state == .on {values.append(clip.id)}; self.preferences.set(values,for:"favorites") }
            controls.addArrangedSubview(star)
            let menu = NSPopUpButton(); let values = clip.id == "idle" ? [1,3,4,6] : [0,1,3,4,6]
            let names = [0:"关闭",1:"很少",3:"偶尔",4:"较常",6:"经常"]
            menu.addItems(withTitles:values.map {names[$0]!}); menu.selectItem(at:values.firstIndex(of:preferences.baseWeight(clip.id)) ?? 0)
            menu.setAccessibilityLabel(clip.title+"出现频率")
            attach(menu) { [weak self] sender in self?.preferences.setWeight(values[(sender as! NSPopUpButton).indexOfSelectedItem],for:clip.id) }
            controls.addArrangedSubview(menu)
        }
        controls.addArrangedSubview(preview)
        let image = NSImageView(); image.image = NSImage(systemSymbolName:"film",accessibilityDescription:nil); image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant:20).isActive = true; image.heightAnchor.constraint(equalToConstant:20).isActive = true
        let name = label(clip.title); let nameStack = NSStackView(views:[image,name]); nameStack.spacing = 8
        fill(alignedRow(leading:nameStack,control:controls),in:stack)
        let options = [("0.75","0.75×"),("1.0","1×（默认）"),("1.25","1.25×"),("1.5","1.5×")]
        fill(popup("此动作播放速度",options:options,value:String(preferences.clipSpeed(clip.id))) { [weak self] in self?.preferences.setSpeed(Double($0)!,for:clip.id) },in:stack)
        return stack
    }
    private func messages() {
        group("输入快捷键",[
            choice("发送与换行","sendShortcut",[("commandReturn","⌘ Command + ↩ Enter 发送"),("returnToSend","↩ Enter 发送")]),
            label("默认：⌘ Command + ↩ Enter 发送，↩ Enter 换行。\n备选：↩ Enter 发送；⇧ Shift + ↩ Enter 或 ⌥ Option + ↩ Enter 换行。\n临时对话和历史对话同步生效，中文输入法选词时不会发送。")])
        group("显示哪些消息",[toggle("任务气泡提醒","taskBubbles"),toggle("任务进展","progressBubbles"),toggle("最终回复","resultBubbles"),toggle("互动台词","interactionBubbles"),label("需要处理的审批、补充输入与任务失败仍保留通知入口。关闭气泡不会停止任务或删除历史。")])
        group("停留时间",[
            slider("互动台词","interactionSeconds",range:0...60,suffix:"秒"),slider("任务进展","progressSeconds",range:0...60,suffix:"秒"),slider("最终回复","resultSeconds",range:0...120,suffix:"秒"),slider("额度信息","quotaSeconds",range:0...120,suffix:"秒"),label("设为 0 秒表示手动关闭。审批、补充输入和失败提示保留到处理或手动关闭。"),
            toggle("长回复自动延长阅读时间","autoReadTime",detail:"最多延长到 120 秒；手动关闭模式不受影响。"),toggle("鼠标移入时暂停倒计时","pauseOnHover"),toggle("文字显示完毕后开始计时","countAfterReveal")])
        group("显示与声音",[toggle("逐步显示文字","typingEffect"),toggle("播放音效","soundEnabled"),row("最终回复时长",control:ActionButton("预览…") { [weak self] in self?.onMessagePreview(.result) })])
        group("安静陪伴",[toggle("安静陪伴模式","quietCompanion",detail:"减少自主活动、停止自动移动，关闭互动台词、进展气泡和音效。最终回复与待处理通知保留。"),toggle("启用专注时段","quietSchedule"),time("开始时间","quietStart"),time("结束时间","quietEnd"),label("按本机时间生效，支持跨午夜；起止相同表示全天。")])
    }
    private func appearance() {
        group("大小",[slider("桌宠大小","petPercent",range:50...200,suffix:"%"),slider("气泡大小","bubblePercent",range:50...150,suffix:"%"),slider("消息文字大小","messageFontSize",range:11...20,suffix:"pt")])
        let well = NSColorWell(); well.color = AppAccent.color; well.widthAnchor.constraint(equalToConstant:70).isActive = true
        attach(well) { [weak self] sender in guard let rgb = (sender as! NSColorWell).color.usingColorSpace(.sRGB) else {return}; self?.preferences.set([rgb.redComponent,rgb.greenComponent,rgb.blueComponent],for:"accentRGB"); self?.preferences.set("custom",for:"accentStyle") }
        group("颜色",[choice("外观模式","appearanceMode",AppAppearance.choices),choice("强调色","accentStyle",AppAccent.choices),row("自定义强调色",control:well)])
        fill(row("气泡效果",control:ActionButton("预览气泡") { [weak self] in self?.onMessagePreview(.preview) }),in:content)
    }
    private func advanced() {
        group("设置文件",[row("导出设置",detail:"只包含本页设置，不含会话、凭证或模型配置。",control:ActionButton("导出…") { [weak self] in self?.exportSettings() }),row("导入设置",detail:"导入前检查全部字段；登录启动项不随设置文件改变。",control:ActionButton("导入…") { [weak self] in self?.importSettings() })])
        group("本机数据",[row("数据目录",detail:Paths.data.path,control:ActionButton("在访达中显示") {if !NSWorkspace.shared.open(Paths.data) {showError("无法打开数据目录",PetFailure(message:Paths.data.path))}})])
        group("恢复",[row("全部恢复为默认值",detail:"保留聊天历史、动画素材和系统登录启动项。",control:ActionButton("恢复为默认值…") { [weak self] in self?.restoreAll() })])
    }
    private func restorePage() {window.makeFirstResponder(nil); preferences.reset(selected.keys); render(); if selected == .appearance || selected == .identity {onMessagePreview(.preview)}}
    private func restoreAll() {
        let alert = NSAlert(); alert.messageText = "将所有设置恢复为默认值？"; alert.informativeText = "名字、动作偏好、消息和外观会恢复默认。聊天历史、动画素材和系统登录启动项保持不变。"
        alert.addButton(withTitle:"取消"); alert.addButton(withTitle:"恢复为默认值"); alert.applyAccent(primary:1)
        alert.beginSheetModal(for:window) { [weak self] response in guard response == .alertSecondButtonReturn, let self else {return}; self.preferences.reset(Array(PetPreferences.defaults.keys)); self.render() }
    }
    private func exportSettings() {
        window.makeFirstResponder(nil)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = PetPreferences.productName+"设置.json"
        panel.beginSheetModal(for:window) { [weak self] response in guard response == .OK, let url = panel.url, let self else {return}; do {try self.preferences.exportData().write(to:url,options:.atomic)} catch {showError("导出设置失败",error)} }
    }
    private func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for:window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else {return}
            do {try self.preferences.importData(Data(contentsOf:url),clipIDs:Set(self.catalog?.all.map(\.id) ?? [])); self.render()}
            catch {showError("导入设置失败",error)}
        }
    }
}
