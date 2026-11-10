import AppKit

final class ActivitySettingsPage {
    private let form:SettingsForm, catalog:Catalog?
    private let reload:() -> Void, onPreview:(Clip) -> Void
    private var preferences:PetPreferences {form.preferences}
    init(form:SettingsForm,catalog:Catalog?,reload:@escaping () -> Void,onPreview:@escaping (Clip) -> Void) {
        self.form = form; self.catalog = catalog; self.reload = reload; self.onPreview = onPreview
    }
    func render() {
        let actions = [("none","无动作"),("chat","临时聊天面板"),("quota","查看额度"),("history","查看历史消息"),("random","显示任务进度、播放随机动画"),("randomAnimation","播放随机动画")]
        form.group("鼠标互动",[form.choice("单击桌宠","singleClickAction",actions),form.choice("双击桌宠","doubleClickAction",actions),form.choice("右键双击桌宠","rightDoubleClickAction",actions)])
        form.group("桌宠吸边",[
            form.toggle("屏幕左右边缘吸边","sideDockEnabled"),
            form.slider("左右露出比例","sideExposurePercent",range:40...85,step:5,suffix:"%",requires:["sideDockEnabled"]),
            form.toggle("顶部刘海吸边","notchDockEnabled",detail:"仅对带刘海的 MacBook 机型的内建屏幕生效。"),
            form.slider("刘海露出比例","notchExposurePercent",range:40...85,step:5,suffix:"%",requires:["notchDockEnabled"])])
        let interval = preferences.number("leisureInterval")
        let preset = interval == 60 ? "60" : interval == 15 ? "15" : interval == 8 ? "8" : "custom"
        form.group("自主活动",[
            form.popup("活跃程度",options:[("60","安静"),("15","适中"),("8","活泼"),("custom","自定义")],value:preset) { [weak self] value in if let seconds = Double(value) {self?.preferences.set(seconds,for:"leisureInterval"); self?.reload()} },
            form.slider("活动间隔","leisureInterval",range:5...180,suffix:"秒",detail:"到达间隔后，当前动作播放完再切换。"),
            form.toggle("自主移动","autoMove"),form.choice("活动范围","movementRange",[("still","原地陪伴"),("nearby","小范围活动"),("screen","整个屏幕")],requires:["autoMove"]),form.toggle("减少重复动作","avoidRepeat",detail:"随机互动和自主活动会减少重复，任务动作始终避免连续重复。"),
            form.slider("整体播放速度","playbackSpeed",range:0.75...1.5,step:0.05,suffix:"×",detail:"同时调整动作和移动速度；与单个动作的速度倍率相乘。")])
        form.group("任务动作",[form.toggle("收到任务时播放开场","taskOpening"),form.toggle("完成任务时播放庆祝","taskCelebration")])
        guard let catalog else {return}
        form.fill(form.note("❤️ 越多，随机播放时越常出现，权重越高。"),in:form.content)
        for (title,clips,automatic,symbol) in [("待机动作",catalog.idles+catalog.extras,true,"figure.stand"),("互动动作",catalog.variants,true,"figure.wave"),("工作动作",catalog.work,true,"brain.head.profile"),("移动动作",catalog.movementAnimations,true,"figure.walk.motion"),("鼠标与额度动作",[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation],false,"hand.rays")] {
            form.group(title,clips.map {clip in animationRow(clip,automatic:automatic,symbol:symbol)})
        }
    }
    private func animationRow(_ clip: Clip, automatic: Bool, symbol:String) -> NSView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let controls = NSStackView(); controls.spacing = 8
        let preview = ActionButton("播放") { [weak self] in self?.onPreview(clip) }; preview.image = NSImage(systemSymbolName:"play.fill",accessibilityDescription:nil); preview.imagePosition = .imageLeading
        if automatic {controls.addArrangedSubview(form.animationWeight(clip))}
        controls.addArrangedSubview(preview)
        let image = NSImageView(); image.image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil); image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant:20).isActive = true; image.heightAnchor.constraint(equalToConstant:20).isActive = true
        let name = label(clip.title)
        name.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        let nameStack = NSStackView(views:[image,name]); nameStack.spacing = 8; nameStack.alignment = .centerY
        controls.alignment = .centerY
        form.fill(form.alignedRow(leading:nameStack,control:controls),in:stack)
        let options = [("0.75","0.75×"),("1.0","1×（默认）"),("1.25","1.25×"),("1.5","1.5×")]
        form.fill(form.popup("此动作播放速度",options:options,value:String(preferences.clipSpeed(clip.id))) { [weak self] in self?.preferences.setSpeed(Double($0)!,for:clip.id) },in:stack)
        return form.searchable(stack,title:clip.title)
    }
}
