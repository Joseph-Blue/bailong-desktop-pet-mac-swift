import AppKit

enum AppIcons {
    static var application: NSImage? {NSImage(contentsOf:Paths.resources.appendingPathComponent("BailongPet.icns"))}
    static func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey:Any] = [
            .applicationName:"白龙桌宠", .applicationVersion:Paths.version,
            .credits:NSAttributedString(string:"Swift + AppKit · 原作 jingh12312-rgb\n本地开发版本，Apple Silicon")
        ]
        if let icon = application {options[.applicationIcon] = icon}
        NSApp.orderFrontStandardAboutPanel(options:options)
        NSApp.activate(ignoringOtherApps:true)
    }
    // 保留素材的透明轮廓，菜单栏交由系统按背景绘制为白/黑剪影。
    static func petSilhouette(_ frame: Frame) -> NSImage {
        let crop = frame.image.cropping(to:frame.bounds.integral) ?? frame.image
        let source = NSImage(cgImage:crop,size:NSSize(width:crop.width,height:crop.height))
        let image = NSImage(size:NSSize(width:18,height:18),flipped:false) { rect in
            let scale = min(rect.width/source.size.width,rect.height/source.size.height)
            let size = NSSize(width:source.size.width*scale,height:source.size.height*scale)
            let fitted = NSRect(x:(rect.width-size.width)/2,y:(rect.height-size.height)/2,width:size.width,height:size.height)
            source.draw(in:fitted)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .sourceIn
            NSColor.white.setFill(); NSBezierPath(rect:fitted).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = "白龙桌宠"
        return image
    }
    static let finder: NSImage = {
        let image = NSImage(size:NSSize(width:22,height:22),flipped:false) { _ in
            NSColor.black.setStroke()
            let outline = NSBezierPath(roundedRect:NSRect(x:2,y:2,width:18,height:18),xRadius:3,yRadius:3)
            outline.lineWidth = 1.5; outline.stroke()
            let face = NSBezierPath(); face.lineWidth = 1.4; face.lineCapStyle = .round; face.lineJoinStyle = .round
            face.move(to:NSPoint(x:11.5,y:19.5)); face.curve(to:NSPoint(x:9.5,y:10),controlPoint1:NSPoint(x:11.5,y:16),controlPoint2:NSPoint(x:10,y:13))
            face.line(to:NSPoint(x:12.5,y:10)); face.line(to:NSPoint(x:12.5,y:2.5))
            face.move(to:NSPoint(x:6.5,y:14.5)); face.line(to:NSPoint(x:6.5,y:13.5))
            face.move(to:NSPoint(x:15.5,y:14.5)); face.line(to:NSPoint(x:15.5,y:13.5))
            face.move(to:NSPoint(x:6,y:8)); face.curve(to:NSPoint(x:16,y:8),controlPoint1:NSPoint(x:8.5,y:5.5),controlPoint2:NSPoint(x:13.5,y:5.5)); face.stroke()
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = "访达中打开"
        return image
    }()
}
