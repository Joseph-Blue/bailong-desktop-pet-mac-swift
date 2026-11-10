import AppKit

final class AppearanceSettingsPage {
    private let form:SettingsForm
    private unowned let window:NSWindow
    private let reload:() -> Void, onPreviewDetails:() -> Void
    private var preferences:PetPreferences {form.preferences}
    private var materialPreview: Bubble?
    private var previewDismissal: DispatchWorkItem?
    private weak var glassSlider: GlassOpacitySlider?
    private weak var glassFollowSwitch: NSSwitch?
    private var glassControls = [NSView]()
    private var accentButtons = [NSButton]()
    private var accentNames = [NSTextField]()
    init(form:SettingsForm,window:NSWindow,reload:@escaping () -> Void,onPreviewDetails:@escaping () -> Void) {
        self.form = form; self.window = window; self.reload = reload; self.onPreviewDetails = onPreviewDetails
    }
    func reset() {dismissPreview(); accentButtons.removeAll(); accentNames.removeAll(); glassControls.removeAll()}
    func refreshAvailability() {
        glassSlider?.isEnabled = !preferences.bool("glassFollowsSystem")
        glassFollowSwitch?.state = preferences.bool("glassFollowsSystem") ? .on : .off
        for view in glassControls {view.alphaValue = preferences.bool("glassFollowsSystem") ? 0.45 : 1}
    }
    func refreshAccent() {
        for (index,button) in accentButtons.enumerated() {
            let chosen = AppAccent.choices[index].0 == preferences.string("accentStyle")
            button.state = chosen ? .on : .off; button.needsDisplay = true
            accentNames[index].stringValue = chosen ? AppAccent.choices[index].1 : ""
        }
    }
    func render() {
        form.group("大小",[form.slider("桌宠大小","petPercent",range:50...200,suffix:"%"),form.slider("气泡大小","bubblePercent",range:50...150,suffix:"%"),form.slider("消息文字大小","messageFontSize",range:11...20,suffix:"pt")])
        form.group("桌宠轮廓",[form.toggle("轮廓阴影","petShadow")])
        form.group("气泡形状",[form.toggle("自定义宽高比","bubbleAspectEnabled"),form.slider("宽 : 高","bubbleAspectRatio",range:0.6...3,step:0.1,suffix:": 1",requires:["bubbleAspectEnabled"])])
        let palette = NSStackView(); palette.spacing = 3; palette.alignment = .top
        for (key,name) in AppAccent.choices {
            let dot = AccentSwatch(key:key,name:name)
            dot.state = preferences.string("accentStyle") == key ? .on : .off
            form.attach(dot) { [weak self] _ in
                guard let self else {return}
                self.preferences.set(key,for:"accentStyle")
                self.reload()
            }
            let caption = NSTextField(labelWithString:dot.state == .on ? name : "")
            caption.font = .systemFont(ofSize:9); caption.textColor = .secondaryLabelColor; caption.alignment = .center
            caption.heightAnchor.constraint(equalToConstant:13).isActive = true
            let column = NSStackView(views:[dot,caption]); column.orientation = .vertical; column.spacing = 2
            column.widthAnchor.constraint(equalToConstant:38).isActive = true
            caption.widthAnchor.constraint(equalTo:column.widthAnchor).isActive = true
            palette.addArrangedSubview(column); accentButtons.append(dot); accentNames.append(caption)
        }
        var themeRows = [form.segmented("外观模式","appearanceMode",AppAppearance.choices,symbols:["system":"circle.lefthalf.filled","light":"sun.max","dark":"moon"]),form.row("强调色",control:palette)]
        if preferences.string("accentStyle") == "custom" {
            let well = CenteredColorWell(); well.color = AppAccent.color; well.widthAnchor.constraint(equalToConstant:70).isActive = true
            form.attach(well) { [weak self] sender in guard let rgb = (sender as! NSColorWell).color.usingColorSpace(.sRGB) else {return}; self?.preferences.set([rgb.redComponent,rgb.greenComponent,rgb.blueComponent],for:"accentRGB") }
            themeRows.append(form.row("自定义",control:well))
        }
        form.group("主题",themeRows)
        var materialImages = [String:NSImage]()
        if let image = glassSymbolImage(filled:false) {
            image.size = NSSize(width:18,height:18); materialImages["glass"] = image
        }
        let material = form.segmented("消息窗口材质","bubbleMaterial",[("glass","液态玻璃"),("plain","普通材质")],symbols:["plain":"rectangle.fill"],images:materialImages,value:preferences.usesGlass ? "glass" : "plain",enabled:PetPreferences.glassAvailable,detail:PetPreferences.glassAvailabilityDescription) { [weak self] in self?.reload(); self?.showPreview() }
        var materialRows = [material]
        if preferences.usesGlass {
            let follow = AccentSwitch(); follow.state = preferences.bool("glassFollowsSystem") ? .on : .off; glassFollowSwitch = follow
            follow.setAccessibilityLabel("液态玻璃跟随系统设定")
            form.attach(follow) { [weak self] sender in self?.preferences.set((sender as! NSSwitch).state == .on,for:"glassFollowsSystem"); self?.showPreview() }
            materialRows.append(form.row("液态玻璃跟随系统设定",control:follow))
            let slider = GlassOpacitySlider(); slider.minValue = 0; slider.maxValue = 1; slider.doubleValue = preferences.number("glassOpacity")
            slider.numberOfTickMarks = 5; slider.allowsTickMarkValuesOnly = false; slider.isContinuous = true
            slider.trackFillColor = AppAccent.color; slider.widthAnchor.constraint(equalToConstant:180).isActive = true
            slider.setAccessibilityLabel("玻璃不透明度"); slider.isEnabled = !preferences.bool("glassFollowsSystem"); glassSlider = slider
            form.attach(slider) { [weak self] sender in self?.preferences.set((sender as! NSSlider).doubleValue,for:"glassOpacity"); self?.showPreview() }
            slider.ended = { [weak self] in self?.schedulePreviewDismissal() }
            let left = glassSymbol(filled:false), right = glassSymbol(filled:true)
            let controls = NSStackView(views:[left,slider,right]); controls.spacing = 8; controls.alignment = .centerY
            controls.widthAnchor.constraint(equalToConstant:244).isActive = true
            controls.alphaValue = slider.isEnabled ? 1 : 0.45; glassControls = [controls]
            materialRows.append(form.row("玻璃不透明度",control:controls))
        }
        materialRows.append(form.toggle("动态效果","bubbleMotion",detail:"控制气泡动画，以及桌宠启动、退出、显示和隐藏时的淡入淡出。"))
        materialRows.append(form.row("气泡效果",control:ActionButton("预览气泡") { [weak self] in self?.showPreview() }))
        form.group("消息窗口",materialRows)
    }
    private func glassSymbolImage(filled:Bool) -> NSImage? {
        let name = "capsule.on.rectangle.liquid.glass" + (filled ? ".fill" : "")
        let image = NSImage(systemSymbolName:name,accessibilityDescription:nil) ?? NSImage(contentsOf:Paths.resources.appendingPathComponent("glass-symbols/"+name+".pdf"))
        image?.isTemplate = true
        return image
    }
    private func glassSymbol(filled:Bool) -> NSImageView {
        let image = glassSymbolImage(filled:filled)
        let view = NSImageView(); view.image = image; view.contentTintColor = .secondaryLabelColor
        view.setAccessibilityLabel(filled ? "更不透明" : "更通透")
        view.widthAnchor.constraint(equalToConstant:24).isActive = true; view.heightAnchor.constraint(equalToConstant:24).isActive = true
        return view
    }
    func showPreview() {
        previewDismissal?.cancel()
        if materialPreview == nil {materialPreview = Bubble(); materialPreview?.onDetails = { [weak self] in self?.onPreviewDetails() }}
        guard let preview = materialPreview else {return}
        if !preview.visible {preview.show(title:preferences.petName,body:preferences.statusLine("greetingTemplate"),kind:"preview",scale:preferences.number("bubblePercent")/100,seconds:0,details:true)}
        guard let screen = window.screen ?? NSScreen.main else {return}
        let visible = screen.visibleFrame, size = preview.targetFrame.size
        let x = min(visible.maxX-size.width-12,max(visible.minX+12,window.frame.maxX+12))
        let y = min(visible.maxY-size.height-12,max(visible.minY+12,window.frame.maxY-size.height-72))
        preview.move(to:NSPoint(x:x,y:y))
        if glassSlider?.tracking != true {schedulePreviewDismissal()}
    }
    private func schedulePreviewDismissal() {
        previewDismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.materialPreview?.hide() }
        previewDismissal = work; DispatchQueue.main.asyncAfter(deadline:.now()+3,execute:work)
    }
    func dismissPreview() {previewDismissal?.cancel(); previewDismissal = nil; materialPreview?.hide()}
    deinit {previewDismissal?.cancel()}
}
