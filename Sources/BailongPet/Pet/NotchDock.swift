import AppKit

// 刘海几何使用当前显示模式的逻辑坐标，不按机型、尺寸或 Retina 倍率猜测。
enum NotchDockGeometry {
    static func region(on screen:NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              CGDisplayIsBuiltin(number.uint32Value) != 0,
              let left = screen.auxiliaryTopLeftArea,let right = screen.auxiliaryTopRightArea else {return nil}
        return region(frame:screen.frame,safeTop:screen.safeAreaInsets.top,
                      left:left,right:right)
    }
    static func region(frame:CGRect,safeTop:CGFloat,left:CGRect,right:CGRect) -> CGRect? {
        guard safeTop > 0,!left.isEmpty,!right.isEmpty,right.minX > left.maxX else {return nil}
        return CGRect(x:left.maxX,y:frame.maxY-safeTop,width:right.minX-left.maxX,height:safeTop).intersection(frame)
    }
    static func canSnap(position:CGPoint,size:CGFloat,area:CGRect,notch:CGRect) -> Bool {
        abs(position.y-area.minY) <= 24 &&
            (notch.minX-24...notch.maxX+24).contains(position.x+size/2)
    }
    static func origin(notch:CGRect,size:CGFloat,desktopTop:CGFloat) -> CGPoint {
        CGPoint(x:notch.midX-size/2,y:desktopTop-notch.minY)
    }
    static func transform(reference:CGRect,size:CGFloat,notchWidth:CGFloat,progress:CGFloat) -> CGAffineTransform {
        guard !reference.isEmpty else {return .identity}
        let scale = 1+(min(1,max(1,notchWidth-12)/reference.width)-1)*progress
        let angle = .pi*progress,center = size/2
        let a = cos(angle)*scale,b = sin(angle)*scale,c = -sin(angle)*scale,d = cos(angle)*scale
        let rotation = CGAffineTransform(a:a,b:b,c:c,d:d,tx:center-a*center-c*center,ty:center-b*center-d*center)
        let bounds = reference.applying(rotation)
        // 完全收纳时倒挂，头到上胸约半身留在窗口顶边下方，身体裁到刘海方向。
        return rotation.concatenating(CGAffineTransform(translationX:(center-bounds.midX)*progress,
            y:(-bounds.minY-bounds.height*0.5)*progress))
    }
}

extension PetController {
    func snapToNotch(on display:NSScreen) -> Bool {
        guard preferences.bool("notchDockEnabled"),let notch = NotchDockGeometry.region(on:display),
              NotchDockGeometry.canSnap(position:position,size:size,area:area(display),notch:notch) else {return false}
        dockRestore = position; dock = "notch"
        notchDockArea = notch; notchDockDisplayID = PetPreferences.displayID(display)
        dockProgress = 0; dockFrom = 0; dockTarget = 1; dockBegan = now
        move(NotchDockGeometry.origin(notch:notch,size:size,desktopTop:top))
        dockAnimating = true; play(catalog.idle,"idle"); return true
    }
    // 显示模式变化或缩放后重读区域；屏幕不再提供刘海时回到正常安全位置。
    func repositionNotchDock() {
        if preferences.bool("notchDockEnabled"),
           let display = NSScreen.screens.first(where:{PetPreferences.displayID($0) == notchDockDisplayID}),
           let notch = NotchDockGeometry.region(on:display) {
            notchDockArea = notch; dockRestore = constrained(dockRestore,screen:display)
            move(NotchDockGeometry.origin(notch:notch,size:size,desktopTop:top))
        } else {
            dock = nil; dockAnimating = false; dockProgress = 0
            notchDockArea = nil; notchDockDisplayID = nil
            move(constrained(dockRestore,screen:screen))
            if let pending {self.pending = nil; play(pending.0,pending.1)}
        }
        view.needsDisplay = true
    }
}
