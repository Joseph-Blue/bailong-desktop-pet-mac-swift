import AppKit

// 设置表单的控件、编辑回调及定位锚点；不拥有窗口导航、搜索或外部服务。
final class SettingsForm:NSObject,NSTextFieldDelegate {
    let content:NSStackView, preferences:PetPreferences
    private unowned let window:NSWindow
    private var actions = [SettingsAction]()
    private var availabilityUpdates = [(PetPreferences) -> Void]()
    private var textActions = [ObjectIdentifier:(String)->Void]()
    private var textEndActions = [ObjectIdentifier:(String)->Void]()
    var identityPreview:NSTextField?
    private let templateEditor = SettingsTemplateEditor()
    private weak var automaticUpdateSwitch:NSSwitch?, diagnosticsSwitch:NSSwitch?
    private var bufferControls = [NSControl]()
    private weak var bufferRow:NSView?
    private(set) var searchAnchors = [String:NSView]()
    private var section:SettingsSection = .general
    var petSymbol:() -> NSImage? = {nil}
    var historyRecoveryReason:() -> String? = {nil}
    init(content:NSStackView,preferences:PetPreferences,window:NSWindow) {
        self.content = content; self.preferences = preferences; self.window = window
        super.init()
        templateEditor.isFieldEditor = true; templateEditor.isRichText = false; templateEditor.allowsUndo = true
    }
    func reset(section:SettingsSection) {
        self.section = section
        searchAnchors.removeAll()
        for view in content.arrangedSubviews {content.removeArrangedSubview(view); view.removeFromSuperview()}
        actions.removeAll(); textActions.removeAll(); textEndActions.removeAll()
        availabilityUpdates.removeAll()
        bufferControls.removeAll(); bufferRow = nil; identityPreview = nil
    }
    func fieldEditor(for client:Any?) -> Any? {
        guard let field = client as? SettingsTemplateField else {return nil}
        templateEditor.allowsTokens = field.allowsTokens; return templateEditor
    }
    func refreshAvailability() {
        diagnosticsSwitch?.state = preferences.bool("showDiagnostics") ? .on : .off
        automaticUpdateSwitch?.state = preferences.bool("automaticallyCheckUpdates") ? .on : .off
        updateBufferAvailability()
        for update in availabilityUpdates {update(preferences)}
    }
    func controlTextDidBeginEditing(_ notification:Notification) {
        (notification.object as? SettingsTemplateField)?.refreshHighlight()
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {return}
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {return}
        textActions[ObjectIdentifier(field)]?(field.stringValue)
        (field as? SettingsTemplateField)?.refreshHighlight()
        identityPreview?.stringValue = preferences.statusLine("greetingTemplate")
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        textEndActions[ObjectIdentifier(field)]?(field.stringValue)
        // 等原生 field editor 退出后，为未聚焦的输入框恢复相同高亮。
        DispatchQueue.main.async { [weak field] in (field as? SettingsTemplateField)?.refreshHighlight() }
    }
    func attach(_ control: NSControl, _ callback: @escaping (NSControl)->Void) {
        let action = SettingsAction(callback); actions.append(action); control.target = action; control.action = #selector(SettingsAction.invoke(_:))
    }
    func fill(_ view: NSView, in stack: NSStackView) {view.translatesAutoresizingMaskIntoConstraints = false; stack.addArrangedSubview(view); view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
    func note(_ text: String) -> NSTextField {
        let field = label(text)
        field.font = .systemFont(ofSize:11); field.textColor = .secondaryLabelColor
        field.identifier = NSUserInterfaceItemIdentifier("settings-explanation")
        return field
    }
    func group(_ title: String, _ rows: [NSView], action:NSView? = nil) {
        let section = NSStackView(); section.orientation = .vertical; section.alignment = .leading; section.spacing = 10
        let heading = label(title,bold:true); heading.font = .systemFont(ofSize:13,weight:.semibold)
        if let action {fill(alignedRow(leading:heading,control:action),in:section)} else {fill(heading,in:section)}
        let surface = SettingsSectionBackground(), items = NSStackView()
        items.orientation = .vertical; items.alignment = .leading; items.spacing = 10
        surface.addSubview(items); items.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([items.leadingAnchor.constraint(equalTo:surface.leadingAnchor,constant:12),items.trailingAnchor.constraint(equalTo:surface.trailingAnchor,constant:-12),items.topAnchor.constraint(equalTo:surface.topAnchor,constant:12),items.bottomAnchor.constraint(equalTo:surface.bottomAnchor,constant:-12)])
        for (index,row) in rows.enumerated() {
            if index > 0 && row.identifier?.rawValue == "settings-explanation" {items.setCustomSpacing(4,after:rows[index-1])}
            if index > 0 && row.identifier?.rawValue != "settings-explanation" {let line = NSBox(); line.boxType = .separator; fill(line,in:items)}
            fill(row,in:items)
        }
        fill(surface,in:section); fill(section,in:content)
        searchAnchors[title] = section
        for row in rows {
            if let key = row.identifier?.rawValue,key.hasPrefix("setting:") {
                searchAnchors[title+"/"+key.dropFirst("setting:".count)] = row
            }
        }
    }
    func searchable(_ view:NSView,title:String) -> NSView {
        view.identifier = .init("setting:"+title); return view
    }
    func row(_ title: String, detail: String? = nil, control: NSView) -> NSView {
        let texts = NSStackView(); texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 4
        fill(label(title),in:texts)
        if let detail {let explanation = label(detail); explanation.font = .systemFont(ofSize:11); explanation.textColor = .secondaryLabelColor; fill(explanation,in:texts)}
        return searchable(alignedRow(leading:texts,control:control),title:title)
    }
    func alignedRow(leading: NSView, control: NSView) -> NSView {
        // 显式固定左右两端；多余宽度留给左侧说明，不拉长开关或按钮。
        let row = NSView()
        compactControl(control)
        if let field = control as? NSTextField, !field.isEditable {field.alignment = .right}
        for view in [leading,control] {view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view)}
        leading.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        control.setContentHuggingPriority(.defaultHigh,for:.horizontal)
        control.setContentCompressionResistancePriority(.defaultHigh,for:.horizontal)
        let compactHeight = row.heightAnchor.constraint(equalToConstant:32); compactHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo:row.leadingAnchor),
            leading.trailingAnchor.constraint(equalTo:control.leadingAnchor,constant:-24),
            leading.centerYAnchor.constraint(equalTo:(control as? SettingsSliderControl)?.slider.centerYAnchor ?? row.centerYAnchor),
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
    private func compactControl(_ view: NSView) {
        if let stack = view as? NSStackView {
            // 普通 contentHugging 不控制 NSStackView 的 gravity 区域间距。
            // fill 让末个控件贴住操作区尾端，内部间距和控件都保持自然宽度。
            stack.distribution = .fill
            stack.setHuggingPriority(.defaultHigh,for:.horizontal)
            stack.edgeInsets = NSEdgeInsets(top:0,left:0,bottom:0,right:0)
            for child in stack.arrangedSubviews {compactControl(child)}
            // 操作组不承担整行的剩余空间；已有明确宽度的滑块组沿用该宽度。
            if !stack.constraints.contains(where: {$0.isActive && $0.firstAttribute == .width && $0.secondItem == nil && $0.relation == .equal}) {
                stack.widthAnchor.constraint(equalToConstant:stack.fittingSize.width.rounded(.up)).isActive = true
            }
        }
    }
    // 只随现有设置通知刷新；离开页面清理回调，不持有旧页面。
    private func dependent(_ view:NSView, requires keys:[String], unless exclusions:[String] = []) -> NSView {
        guard !keys.isEmpty || !exclusions.isEmpty else {return view}
        let update:(PetPreferences) -> Void = { [weak view] preferences in
            guard let view else {return}
            let enabled = keys.allSatisfy {preferences.bool($0)} && exclusions.allSatisfy {!preferences.bool($0)}
            func apply(_ child:NSView) {
                if let control = child as? NSControl {control.isEnabled = enabled}
                else {for child in child.subviews {apply(child)}}
            }
            apply(view)
            view.alphaValue = enabled ? 1 : 0.45
        }
        availabilityUpdates.append(update); update(preferences)
        return view
    }
    func toggle(_ title: String, _ key: String, detail: String? = nil, enabled:Bool = true, requires:[String] = [], unless:[String] = []) -> NSView {
        let control = AccentSwitch(); control.state = preferences.bool(key) ? .on : .off; control.isEnabled = enabled; control.setAccessibilityLabel(title)
        if key == "recordHistory" && historyRecoveryReason() != nil {control.isEnabled = false}
        if key == "showDiagnostics" { diagnosticsSwitch = control }
        if key == "automaticallyCheckUpdates" { automaticUpdateSwitch = control }
        attach(control) { [weak self] sender in self?.preferences.set((sender as! NSSwitch).state == .on,for:key) }
        return dependent(row(title,detail:detail,control:control),requires:requires,unless:unless)
    }
    func popup(_ title: String, options: [(String,String)], value: String, width: CGFloat = 190, identifier: String? = nil, detail:String? = nil, changed: @escaping (String)->Void) -> NSView {
        let menu = NSPopUpButton(); menu.addItems(withTitles:options.map(\.1)); menu.selectItem(at:options.firstIndex {$0.0 == value} ?? 0)
        if let identifier {menu.identifier = NSUserInterfaceItemIdentifier(identifier)}
        var controlWidth = width
        if identifier == "animationQuality" || identifier == "sendShortcut" {
            let font = NSFont.systemFont(ofSize:NSFont.systemFontSize)
            let columns = options.map {$0.1.components(separatedBy:"\t")}
            let tab:CGFloat = identifier == "sendShortcut"
                ? (columns.map {(($0[0]) as NSString).size(withAttributes:[.font:font]).width}.max() ?? 0)+24 : 64
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment:.left,location:tab)]
            for item in menu.itemArray {
                item.attributedTitle = NSAttributedString(string:item.title,attributes:[.font:font,.paragraphStyle:paragraph])
            }
            if identifier == "sendShortcut" {
                let trailingWidth = columns.map {(($0.last!) as NSString).size(withAttributes:[.font:font]).width}.max() ?? 0
                controlWidth = max(width,tab+trailingWidth+40)
            }
        }
        menu.widthAnchor.constraint(equalToConstant:controlWidth).isActive = true; menu.setAccessibilityLabel(title)
        attach(menu) {sender in let index = (sender as! NSPopUpButton).indexOfSelectedItem; if options.indices.contains(index) {changed(options[index].0)}}
        return row(title,detail:detail,control:menu)
    }
    func choice(_ title: String, _ key: String, _ options: [(String,String)],detail:String? = nil,requires:[String] = []) -> NSView {
        let width:CGFloat = ["sendShortcut","singleClickAction","doubleClickAction","rightDoubleClickAction"].contains(key) ? 260 : key == "animationQuality" ? 250 : 190
        let result = popup(title,options:options,value:preferences.string(key),width:width,identifier:key,detail:detail) { [weak self] value in
            self?.preferences.set(value,for:key)
            self?.identityPreview?.stringValue = self?.preferences.statusLine("greetingTemplate") ?? ""
        }
        return dependent(result,requires:requires)
    }
    func segmented(_ title:String,_ key:String,_ options:[(String,String)],symbols:[String:String] = [:],images:[String:NSImage] = [:],value:String? = nil,enabled:Bool = true,detail:String? = nil,changed:(() -> Void)? = nil) -> NSView {
        let control = NSSegmentedControl(labels:options.map(\.1),trackingMode:.selectOne,target:nil,action:nil)
        control.selectedSegment = options.firstIndex {$0.0 == (value ?? preferences.string(key))} ?? 0
        control.isEnabled = enabled; control.identifier = .init(key); control.setAccessibilityLabel(title)
        for (index,option) in options.enumerated() {
            let image = images[option.0] ?? symbols[option.0].flatMap {NSImage(systemSymbolName:$0,accessibilityDescription:nil)}
            if let image {control.setImage(image,forSegment:index)}
        }
        attach(control) { [weak self] sender in
            let index = (sender as! NSSegmentedControl).selectedSegment
            guard options.indices.contains(index) else {return}
            self?.preferences.set(options[index].0,for:key); changed?()
        }
        return row(title,detail:detail,control:control)
    }
    func entry(_ title: String, value: String, placeholder: String = "", emptyFallback:String? = nil, limit: Int = 20, allowsTokens:Bool = true, icon:NSImage? = nil, tokenHint:String? = nil, changed: @escaping (String)->Void) -> NSView {
        let value = value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? emptyFallback ?? value : value
        let field: NSTextField = section == .identity ? SettingsTemplateField(string:value) : NSTextField(string:value)
        let templateField = field as? SettingsTemplateField
        templateField?.allowsTokens = allowsTokens
        field.placeholderString = placeholder; field.delegate = self
        templateField?.refreshHighlight(); field.setAccessibilityLabel(title)
        let count = NSTextField(labelWithString:"")
        count.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular); count.alignment = .right
        count.widthAnchor.constraint(equalToConstant:54).isActive = true
        let clear = NSButton(image:NSImage(systemSymbolName:"xmark.circle.fill",accessibilityDescription:"清空"+title)!,target:nil,action:nil)
        clear.isBordered = false; clear.contentTintColor = .secondaryLabelColor
        clear.setAccessibilityLabel("清空"+title)
        clear.widthAnchor.constraint(equalToConstant:20).isActive = true
        clear.heightAnchor.constraint(equalToConstant:24).isActive = true
        let updateCount: (String)->Void = {value in
            let length = allowsTokens ? TemplateSyntax.count(value) : value.count
            count.stringValue = "\(length)/\(limit)"
            count.textColor = length >= limit ? .systemRed : .secondaryLabelColor
            count.setAccessibilityLabel("已输入 \(length) 字，上限 \(limit) 字")
            clear.isEnabled = !value.isEmpty
        }
        updateCount(value)
        textActions[ObjectIdentifier(field)] = {text in
            let bounded = allowsTokens ? TemplateSyntax.bounded(text,limit:limit) : String(text.prefix(limit))
            if bounded != text {
                if let editor = field.currentEditor() as? NSTextView {
                    let selection = editor.selectedRange(); editor.string = bounded
                    editor.setSelectedRange(NSRange(location:min(selection.location,(bounded as NSString).length),length:0))
                }
                field.stringValue = bounded
            }
            updateCount(bounded); changed(bounded)
        }
        if let emptyFallback {
            textEndActions[ObjectIdentifier(field)] = { [weak self,weak field] text in
                guard text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,let self,let field else {return}
                field.stringValue = emptyFallback
                self.textActions[ObjectIdentifier(field)]?(emptyFallback)
                (field as? SettingsTemplateField)?.refreshHighlight()
                self.identityPreview?.stringValue = self.preferences.statusLine("greetingTemplate")
            }
        }
        attach(clear) { [weak self,weak field] _ in
            guard let self,let field else {return}
            self.window.makeFirstResponder(field)
            let replacement = emptyFallback ?? ""
            if let editor = field.currentEditor() as? NSTextView {
                let all = NSRange(location:0,length:(editor.string as NSString).length)
                if editor.shouldChangeText(in:all,replacementString:replacement) {
                    editor.replaceCharacters(in:all,with:replacement); editor.didChangeText()
                    editor.setSelectedRange(NSRange(location:0,length:(replacement as NSString).length))
                }
            } else {
                field.stringValue = replacement; self.textActions[ObjectIdentifier(field)]?(replacement); (field as? SettingsTemplateField)?.refreshHighlight()
            }
        }
        let controls = NSStackView(views:[field,clear,count]); controls.orientation = .horizontal; controls.spacing = 6; controls.alignment = .centerY; controls.distribution = .fill
        field.setContentHuggingPriority(.defaultLow,for:.horizontal)
        field.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        if limit >= 120 {
            // 台词标签在上，输入横向铺满；不再给短标签留出大半行空白。
            field.usesSingleLineMode = false; field.maximumNumberOfLines = 0
            field.cell?.wraps = true; field.cell?.isScrollable = false
            field.heightAnchor.constraint(equalToConstant:52).isActive = true
            let row = NSStackView(); row.orientation = .vertical; row.alignment = .leading; row.spacing = 8
            fill(label(title),in:row); fill(controls,in:row)
            return searchable(row,title:title)
        }
        field.widthAnchor.constraint(equalToConstant:240).isActive = true
        let caption = identityLabel(title,token:tokenHint)
        let leading = NSStackView(); leading.orientation = .horizontal; leading.alignment = .centerY; leading.spacing = 6
        if let icon {
            let image = NSImageView(image:icon); image.contentTintColor = .secondaryLabelColor
            image.widthAnchor.constraint(equalToConstant:18).isActive = true; image.heightAnchor.constraint(equalToConstant:18).isActive = true
            leading.addArrangedSubview(image)
        }
        leading.addArrangedSubview(caption)
        return searchable(alignedRow(leading:leading,control:controls),title:title)
    }
    private func identityLabel(_ title:String,token:String?) -> NSView {
        guard let token,let item = SettingsTemplateTokens.items.first(where:{$0.token == token}) else {return label(title)}
        let row = NSStackView(views:[label(title),SettingsTokenBadge(token:token,color:item.color)])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 6
        return row
    }
    func text(_ title: String, _ key: String, placeholder: String = "", limit: Int = 20) -> NSView {
        let icon:NSImage?
        switch key {
        case "ownerName": icon = NSImage(systemSymbolName:"person.crop.circle",accessibilityDescription:nil)
        case "petName": icon = petSymbol()
        case "customAddress": icon = NSImage(systemSymbolName:"person.text.rectangle",accessibilityDescription:nil)
        default: icon = nil
        }
        let token = ["ownerName":"{用户名}","petName":"{桌宠名}","customAddress":"{特定称呼}"][key]
        let fallback = ["ownerName":"主人","petName":"白龙娘"][key]
            ?? (key.hasSuffix("Template") ? PetPreferences.defaults[key] as? String : nil)
        return entry(title,value:preferences.string(key),placeholder:placeholder,emptyFallback:fallback,limit:limit,allowsTokens:!["ownerName","petName"].contains(key),icon:icon,tokenHint:token) { [weak self] value in self?.preferences.set(value,for:key) }
    }
    func slider(_ title:String,_ key:String,range:ClosedRange<Double>,step:Double = 1,suffix:String,detail:String? = nil,requires:[String] = []) -> NSView {
        let controls = numericSlider(title,value:preferences.number(key),range:range,step:step,suffix:suffix) { [weak self] value in self?.preferences.set(value,for:key) }
        return dependent(row(title,detail:detail,control:controls),requires:requires)
    }
    func animationWeight(_ clip:Clip) -> NSView {
        let minimum = clip.id == "idle" ? 1.0 : 0.0
        return numericSlider(clip.title+"随机播放权重",value:preferences.weight(clip.id),range:minimum...12,step:1,suffix:"❤️",limitSuffix:"") { [weak self] value in
            self?.preferences.setWeight(Int(value),for:clip.id)
        }
    }
    private func numericSlider(_ title:String,value:Double,range:ClosedRange<Double>,step:Double,suffix:String,limitSuffix:String? = nil,color:NSColor? = nil,changed:@escaping (Double) -> Void) -> SettingsSliderControl {
        let slider = NSSlider(value:value,minValue:range.lowerBound,maxValue:range.upperBound,target:nil,action:nil)
        slider.isContinuous = true; slider.trackFillColor = AppAccent.color; slider.widthAnchor.constraint(equalToConstant:180).isActive = true
        slider.setAccessibilityLabel(title)
        let number = NSTextField(string:""); number.alignment = .right; number.widthAnchor.constraint(equalToConstant:54).isActive = true
        number.setAccessibilityLabel(title); (number.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        let formatter = NumberFormatter(); formatter.minimum = NSNumber(value:range.lowerBound); formatter.maximum = NSNumber(value:range.upperBound)
        formatter.maximumFractionDigits = step < 1 ? 2 : 0; formatter.usesGroupingSeparator = false; number.formatter = formatter
        number.doubleValue = slider.doubleValue
        let commit:(Double) -> Void = { value in
            let value = max(range.lowerBound,min(range.upperBound,(value/step).rounded()*step))
            number.doubleValue = value; slider.doubleValue = value; changed(value)
        }
        attach(slider) {commit($0.doubleValue)}; attach(number) {commit($0.doubleValue)}
        let unit = label(suffix); unit.font = .systemFont(ofSize:11); unit.textColor = color ?? .secondaryLabelColor
        if let color {number.textColor = color}
        unit.widthAnchor.constraint(equalToConstant:22).isActive = true
        let unitText = limitSuffix ?? suffix
        let ending = unitText.isEmpty ? "" : " "+unitText
        let limits:(String,String)? = suffix == "%" && range.lowerBound == 0 && range.upperBound == 100 ? nil :
            (formatter.string(from:NSNumber(value:range.lowerBound))!+ending,formatter.string(from:NSNumber(value:range.upperBound))!+ending)
        let steps = Int(((range.upperBound-range.lowerBound)/step).rounded())
        return SettingsSliderControl(number:number,unit:unit,slider:slider,limits:limits,ticks:steps <= 12 ? steps+1 : 7)
    }
    func bufferFrames() -> NSView {
        let slider = NSSlider(value: Double(preferences.animationBufferFrames), minValue: 6, maxValue: 240, target: nil, action: nil)
        slider.isContinuous = false; slider.trackFillColor = AppAccent.color
        slider.numberOfTickMarks = 7; slider.tickMarkPosition = .below; slider.allowsTickMarkValuesOnly = false
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        slider.setAccessibilityLabel("动画缓冲帧数")
        let number = NSTextField(string: String(preferences.animationBufferFrames))
        number.alignment = .right; number.widthAnchor.constraint(equalToConstant: 54).isActive = true
        number.setAccessibilityLabel("输入动画缓冲帧数"); number.delegate = self
        // 不用 formatter 阻止退出非法输入；提交时统一回到默认值。
        let commit: (String) -> Void = { [weak self] text in
            guard let self else { return }
            let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
            let value = parsed.flatMap { (6...240).contains($0) ? $0 : nil } ?? (PetPreferences.defaults["animationBufferFrames"] as! Int)
            number.integerValue = value; slider.integerValue = value
            if self.preferences.animationBufferFrames != value { self.preferences.set(value, for: "animationBufferFrames") }
        }
        textEndActions[ObjectIdentifier(number)] = commit
        attach(number) { sender in commit(sender.stringValue) }
        attach(slider) { sender in commit(String(Int(sender.doubleValue.rounded()))) }
        let unit = label("帧"); unit.font = .systemFont(ofSize:11); unit.textColor = .secondaryLabelColor
        unit.widthAnchor.constraint(equalToConstant:22).isActive = true
        let controls = SettingsSliderControl(number:number,unit:unit,slider:slider,limits:("6 帧","240 帧"),ticks:7)
        let result = row("动画缓冲帧数", detail:"限制播放中保留的后续帧数；起播准备约四分之一秒。", control: controls)
        bufferControls = [slider, number]; bufferRow = result; updateBufferAvailability()
        return result
    }
    func time(_ title: String, _ key: String, requires:[String] = []) -> NSView {
        let picker = NSDatePicker(); picker.datePickerStyle = .textFieldAndStepper; picker.datePickerElements = [.hourMinute]; picker.locale = Locale(identifier:"zh_CN")
        let minutes = Int(preferences.number(key)); picker.dateValue = Calendar.current.date(from:DateComponents(year:2026,month:1,day:1,hour:minutes/60,minute:minutes%60))!
        picker.setAccessibilityLabel(title)
        attach(picker) { [weak self] sender in let c = Calendar.current.dateComponents([.hour,.minute],from:(sender as! NSDatePicker).dateValue); self?.preferences.set((c.hour ?? 0)*60+(c.minute ?? 0),for:key) }
        return dependent(row(title,control:picker),requires:requires)
    }
    func updateBufferAvailability() {
        let enabled = !preferences.bool("preloadWholeAnimation")
        for control in bufferControls { control.isEnabled = enabled }
        bufferRow?.alphaValue = enabled ? 1 : 0.45
    }
}
