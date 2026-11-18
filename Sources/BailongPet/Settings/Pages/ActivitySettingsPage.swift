import AppKit

final class ActivitySettingsPage {
    private let form:SettingsForm, catalog:Catalog?
    private let reload:() -> Void
    private var preferences:PetPreferences {form.preferences}
    init(form:SettingsForm,catalog:Catalog?,reload:@escaping () -> Void) {
        self.form = form; self.catalog = catalog; self.reload = reload
    }
    func render(manage:@escaping () -> Void) {
        let actions = [("none","无动作"),("chat","临时聊天面板"),("quota","查看额度"),("history","查看历史消息"),("random","显示任务进度、播放随机动画"),("randomAnimation","播放随机动画")]
        form.group("鼠标互动",[form.choice("单击桌宠","singleClickAction",actions),form.choice("双击桌宠","doubleClickAction",actions),form.choice("右键双击桌宠","rightDoubleClickAction",actions)],symbol:"computermouse")
        form.group("桌宠吸边",[
            form.toggle("屏幕左右边缘吸边","sideDockEnabled"),
            form.slider("左右露出比例","sideExposurePercent",range:40...85,step:5,suffix:"%",requires:["sideDockEnabled"]),
            form.toggle("顶部刘海吸边","notchDockEnabled",detail:"仅对带刘海的 MacBook 机型的内建屏幕生效。",symbol:"macbook.gen2"),
            form.slider("从刘海露出比例","notchExposurePercent",range:40...85,step:5,suffix:"%",requires:["notchDockEnabled"])],symbol:"rectangle.inset.filled")
        let interval = preferences.number("leisureInterval")
        let preset = interval == 60 ? "60" : interval == 15 ? "15" : interval == 8 ? "8" : "custom"
        form.group("自主活动",[
            form.popup("活跃程度",options:[("60","安静"),("15","适中"),("8","活泼"),("custom","自定义")],value:preset) { [weak self] value in if let seconds = Double(value) {self?.preferences.set(seconds,for:"leisureInterval"); self?.reload()} },
            form.slider("活动间隔","leisureInterval",range:5...180,suffix:"秒",detail:"到达间隔后，当前动作播放完再切换。"),
            form.toggle("自主移动","autoMove"),form.choice("活动范围","movementRange",[("still","原地陪伴"),("nearby","小范围活动"),("screen","整个屏幕")],requires:["autoMove"]),form.toggle("减少重复动作","avoidRepeat",detail:"随机互动和自主活动会减少重复，任务动作始终避免连续重复。"),
            form.slider("整体播放速度","playbackSpeed",range:0.75...1.5,step:0.05,suffix:"×",detail:"同时调整动作和移动速度；与单个动作的速度倍率相乘。")],symbol:"figure.walk.motion",action:catalog.map { _ in form.navigationButton(SettingsDetail.actions.title,action:manage) })
        form.group("任务动作",[form.toggle("收到任务时播放开场","taskOpening"),form.toggle("完成任务时播放庆祝","taskCelebration")],symbol:"checklist")
    }
    static func items(catalog:Catalog?) -> [SettingsListItem] {
        guard let catalog else {return []}
        var items = [SettingsListItem]()
        for (group,clips,weighted) in [("待机动作",catalog.idles+catalog.extras,true),("互动动作",catalog.variants,true),
            ("工作动作",catalog.work,true),("移动动作",catalog.movementAnimations,true),
            ("鼠标与额度动作",[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation],false)] {
            items += clips.map {.init(group:group,title:$0.title,kind:.animation($0,weighted:weighted),keywords:"动画 播放速度 倍速 频率 偏爱 权重 ❤ ❤️ 爱心 预览")}
        }
        return items
    }
}
