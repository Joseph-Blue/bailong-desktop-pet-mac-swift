import AppKit

// 用户展开内容时使用一次原生过渡；不缩放正文，不创建刷新计时器。
enum DisclosureMotion {
    static var enabled:Bool {ProgressTextEffects.enabled}
    static func update(in view:NSView,animatesLayout:Bool = true,_ changes:() -> Void) {
        let visible = view.window?.isVisible == true && !view.isHiddenOrHasHiddenAncestor
        let surface = view.enclosingScrollView?.contentView ?? view
        if enabled && visible {
            surface.wantsLayer = true
            let transition = CATransition(); transition.type = .fade; transition.duration = 0.16
            transition.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            surface.layer?.add(transition,forKey:"disclosure")
            if animatesLayout {
                NSAnimationContext.runAnimationGroup {context in
                    context.duration = 0.16; context.allowsImplicitAnimation = true
                    changes(); view.layoutSubtreeIfNeeded()
                }
            } else {changes()}
        } else {surface.layer?.removeAnimation(forKey:"disclosure"); changes()}
    }
}
