import AppKit

@main
struct PlaybackRegression {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        func check(_ valid: Bool, _ message: String) {if !valid {fputs("失败：\(message)\n",stderr); exit(1)}}
        func pump(_ seconds: Double) {RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
        func wait(_ message: String, until condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(10)
            while !condition() && Date() < deadline {pump(0.02)}
            check(condition(),message)
        }
        let suite = "BailongPlaybackRegression."+UUID().uuidString
        let defaults = UserDefaults(suiteName:suite)!
        defaults.set(false,forKey:"autoFullscreen"); defaults.set(false,forKey:"autoMove")
        defer {defaults.removePersistentDomain(forName:suite)}
        let catalog = try Catalog.load(), start = Date()
        let pet = PetController(catalog:catalog,defaults:defaults)
        defer {pet.close()}
        check(pet.petPercent == 100 && pet.bubblePercent == 100,"首次默认比例不是 100%")
        wait("默认待机未解码完成") {!pet.loading}
        print(String(format:"默认待机冷解码：%.2f 秒",Date().timeIntervalSince(start)))
        let idleIndex = pet.frameIndex; pump(0.35)
        check(pet.frameIndex != idleIndex,"idle 时间轴未推进")
        // 让三段常用动作完成预热；不启动任务服务。
        pump(2)
        let work = catalog.work[1], old = pet.current.id, oldRect = pet.drawRect
        pet.play(work,"working")
        check(pet.current.id == old && pet.drawRect == oldRect,"加载期间提前使用新动作校准")
        let loadingIndex = pet.frameIndex; pet.began -= 0.4; pet.tick()
        check(pet.frameIndex != loadingIndex,"加载期间旧动画被冻结")
        wait("working 未解码完成") {!pet.loading && pet.current.id == work.id}
        let workIndex = pet.frameIndex; pump(0.35)
        check(pet.frameIndex != workIndex,"working 时间轴未推进")
        let beforeBubble = pet.bubble.window.frame.origin
        pet.say("固定锚点"); let anchor = pet.bubble.window.frame.origin
        pump(0.35); pet.placeBubble()
        check(anchor == pet.bubble.window.frame.origin,"气泡随动画帧摇摆")
        _ = beforeBubble
        pet.play(catalog.dragAnimation,"drag")
        wait("拖拽动作缺失") {!pet.loading && pet.current.id == catalog.dragAnimation.id}
        let dragIndex = pet.frameIndex; pump(0.35)
        check(pet.frameIndex != dragIndex,"拖拽动画未推进")
        pet.play(catalog.landingAnimation,"landing")
        wait("落地动作缺失") {!pet.loading && pet.current.id == catalog.landingAnimation.id}
        check(pet.mode == "landing","普通拖拽松开未播放落地")
        pet.dock = "left"; pet.dockProgress = 1; pet.dockFrom = 1; pet.dockTarget = 0; pet.dockAnimating = true; pet.dockBegan = pet.now
        pet.tick(); let first = pet.dockProgress
        pump(0.12); let middle = pet.dockProgress
        check(first > 0.8 && middle < first && middle > 0,"吸边展开过渡不连续")
        pump(0.25); check(pet.dock == nil && pet.dockProgress == 0,"吸边过渡未完成")
        let down = NSEvent.mouseEvent(with:.leftMouseDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:pet.window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
        let move = NSEvent.mouseEvent(with:.leftMouseDragged,location:.zero,modifierFlags:[],timestamp:0,windowNumber:pet.window.windowNumber,context:nil,eventNumber:2,clickCount:1,pressure:1)!
        let up = NSEvent.mouseEvent(with:.leftMouseUp,location:.zero,modifierFlags:[],timestamp:0,windowNumber:pet.window.windowNumber,context:nil,eventNumber:3,clickCount:1,pressure:0)!
        pet.dock = "left"; pet.dockProgress = 1; pet.mouseDown(down)
        pet.press = NSPoint(x:NSEvent.mouseLocation.x-90,y:NSEvent.mouseLocation.y)
        pet.mouseDragged(move)
        check(pet.dragged && pet.dockAnimating && pet.dockTarget == 0,"吸边拖动没有触发召回")
        pet.mouseUp(up)
        wait("吸边拖动召回未完成") {pet.dock == nil && !pet.loading && pet.mode == "idle"}
        pet.move(pet.constrained(CGPoint(x:pet.area(pet.screen).midX-pet.size/2,y:pet.area(pet.screen).midY-pet.size/2),screen:pet.screen))
        pet.mouseDown(down); pet.press = NSPoint(x:NSEvent.mouseLocation.x-30,y:NSEvent.mouseLocation.y); pet.mouseDragged(move); pet.mouseUp(up)
        wait("普通拖拽松开未切换落地") {!pet.loading && pet.mode == "landing"}
        print("通过：100% 默认值、idle/working 连续播放、加载期间校准、稳定气泡、拖拽/落地、吸边展开及拖动召回。")

        let quota = QuotaPresentation.overview(["rateLimits":["limitName":NSNull(),"planType":"prolite","primary":["usedPercent":40,"windowDurationMins":10080]]],account:nil)
        check(quota.plan == "Pro 100" && quota.rows[0].title == "每周额度" && quota.rows[0].remaining == 60,"套餐或剩余额度错误")
        for key in QuotaPresentation.plans.keys {check(!QuotaPresentation.plan(key,account:nil).contains("null"),"套餐未覆盖")}
        check(QuotaPresentation.plan(nil,account:nil) == "套餐信息暂不可用","缺失套餐未兜底")
        check(QuotaPresentation.plan("unknown",account:nil) == "套餐未识别","未知套餐未兜底")
        check(QuotaPresentation.plan(nil,account:["type":"apiKey"]) == "API 按量计费","API 账号未兜底")
        let ui = ChatInterface(); ui.composer.contentView?.layoutSubtreeIfNeeded(); ui.history.contentView?.layoutSubtreeIfNeeded()
        check(ui.composer.standardWindowButton(.zoomButton)?.isHidden != false && ui.composer.standardWindowButton(.miniaturizeButton)?.isHidden != false,"小窗仍有黄绿按钮")
        ui.showFailure(AppFailure.codex("The model requires a newer version of Codex"),restore:{})
        ui.composer.contentView?.layoutSubtreeIfNeeded()
        check(ui.composerButton.isHidden,"错误页仍显示发送按钮")
        ui.clearFailure(); check(!ui.composerButton.isHidden,"错误页无法返回输入")
        let screen = NSRect(x:-1440,y:80,width:1440,height:820), petRect = NSRect(x:-280,y:90,width:256,height:256)
        let menu = MenuPlacement.frame(size:NSSize(width:240,height:600),cursor:NSPoint(x:-80,y:130),screen:screen,pet:petRect)
        check(screen.contains(menu) && !menu.intersects(petRect),"菜单越界或遮挡桌宠")
        let tall = MenuPlacement.frame(size:NSSize(width:240,height:1200),cursor:NSPoint(x:-80,y:130),screen:screen,pet:petRect)
        check(screen.contains(tall),"超高菜单视口越界")
        print("通过：套餐与缺失值、错误恢复页、窗口按钮、负坐标屏幕菜单定位。")
    }
}
