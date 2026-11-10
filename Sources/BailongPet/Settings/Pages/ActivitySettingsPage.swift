import AppKit

final class ActivitySettingsPage {
    private let form:SettingsForm, catalog:Catalog?
    private let reload:() -> Void, onPreview:(Clip) -> Void
    private var preferences:PetPreferences {form.preferences}
    init(form:SettingsForm,catalog:Catalog?,reload:@escaping () -> Void,onPreview:@escaping (Clip) -> Void) {
        self.form = form; self.catalog = catalog; self.reload = reload; self.onPreview = onPreview
    }
    func render() {
        let actions = [("none","无动作"),("chat","临时聊天面板"),("quota","查看额度"),("history","查看历史消息"),("random","显示任务进度、播放随机动画")]
        form.group("鼠标互动",[form.choice("单击桌宠","singleClickAction",actions),form.choice("双击桌宠","doubleClickAction",actions),form.choice("右键双击桌宠","rightDoubleClickAction",actions)])
        form.group("吸边",[
            form.toggle("收进刘海","notchDockEnabled",detail:"拖到刘海下方松开后倒挂收纳，单击或拖动召回。收纳大小最高为桌宠默认 100%，更小的保持原大小。默认开启，仅带刘海的内置屏幕生效。"),
            form.slider("露出比例","notchExposurePercent",range:40...85,step:5,suffix:"%",detail:"默认露出 55%；收纳时调整立即生效。")])
        let interval = preferences.number("leisureInterval")
        let preset = interval == 60 ? "60" : interval == 15 ? "15" : interval == 8 ? "8" : "custom"
        form.group("自主活动",[
            form.popup("活跃程度",options:[("60","安静"),("15","适中"),("8","活泼"),("custom","自定义")],value:preset) { [weak self] value in if let seconds = Double(value) {self?.preferences.set(seconds,for:"leisureInterval"); self?.reload()} },
            form.slider("活动间隔","leisureInterval",range:5...180,suffix:"秒",detail:"到达间隔后，当前动作播放完再切换。"),
            form.toggle("自主移动","autoMove"),form.choice("活动范围","movementRange",[("still","原地陪伴"),("nearby","小范围活动"),("screen","整个屏幕")],requires:["autoMove"]),form.toggle("减少重复动作","avoidRepeat",detail:"用于随机互动、自主额外动作和移动；任务中固定排除上一动作，普通待机与吸边按各自频率选择。"),
            form.slider("整体播放速度","playbackSpeed",range:0.75...1.5,step:0.05,suffix:"×",detail:"动作和位移使用同一时间轴。单个动作倍率会与整体倍率相乘。")])
        form.group("任务动作",[form.toggle("收到任务时播放开场","taskOpening"),form.toggle("完成任务时播放庆祝","taskCelebration")])
        guard let catalog else {return}
        for (title,clips,automatic) in [("待机动作",catalog.idles+catalog.extras,true),("互动动作",catalog.variants,true),("工作动作",catalog.work,true),("移动动作",catalog.movementAnimations,true),("鼠标与额度动作",[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation],false)] {
            form.group(title,clips.map {clip in animationRow(clip,automatic:automatic)})
        }
        form.fill(form.note("默认普通待机按 4:1、吸边按 7:3 选择；任务中按 35:65 选择工作／待机组，排除上一动作，组内默认均匀选择。频率和偏爱在各场景默认权重上调整。手动预览和明确的拖拽、落地、额度及任务事件不受随机频率影响。默认待机始终保留。"),in:form.content)
    }
    private func animationRow(_ clip: Clip, automatic: Bool) -> NSView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        let controls = NSStackView(); controls.spacing = 8
        let preview = ActionButton("播放") { [weak self] in self?.onPreview(clip) }; preview.image = NSImage(systemSymbolName:"play.fill",accessibilityDescription:nil); preview.imagePosition = .imageLeading
        if automatic {
            let star = AccentChoiceButton(title:"偏爱",type:.switch); star.state = preferences.favorites.contains(clip.id) ? .on : .off
            form.attach(star) { [weak self] sender in guard let self else {return}; var values = self.preferences.favorites.filter {$0 != clip.id}; if (sender as! NSButton).state == .on {values.append(clip.id)}; self.preferences.set(values,for:"favorites") }
            controls.addArrangedSubview(star)
            let menu = NSPopUpButton(); let values = clip.id == "idle" ? [1,3,4,6] : [0,1,3,4,6]
            let names = [0:"关闭",1:"很少",3:"偶尔",4:"较常",6:"经常"]
            menu.addItems(withTitles:values.map {names[$0]!}); menu.selectItem(at:values.firstIndex(of:preferences.baseWeight(clip.id)) ?? 0)
            menu.setAccessibilityLabel(clip.title+"出现频率")
            form.attach(menu) { [weak self] sender in self?.preferences.setWeight(values[(sender as! NSPopUpButton).indexOfSelectedItem],for:clip.id) }
            controls.addArrangedSubview(menu)
        }
        controls.addArrangedSubview(preview)
        let image = NSImageView(); image.image = NSImage(systemSymbolName:"film",accessibilityDescription:nil); image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant:20).isActive = true; image.heightAnchor.constraint(equalToConstant:20).isActive = true
        let name = label(clip.title); let nameStack = NSStackView(views:[image,name]); nameStack.spacing = 8
        form.fill(form.alignedRow(leading:nameStack,control:controls),in:stack)
        let options = [("0.75","0.75×"),("1.0","1×（默认）"),("1.25","1.25×"),("1.5","1.5×")]
        form.fill(form.popup("此动作播放速度",options:options,value:String(preferences.clipSpeed(clip.id))) { [weak self] in self?.preferences.setSpeed(Double($0)!,for:clip.id) },in:stack)
        return form.searchable(stack,title:clip.title)
    }
}
