import AppKit

enum AppIcons {
    // 模板图来自 OpenAI 桌面端的 chatgptTemplate@2x.png；原图随本地资源打包。
    static let openAI: NSImage? = {
        if let image = NSImage(contentsOf:Paths.resources.appendingPathComponent("openai-logo.png")) {
            image.size = NSSize(width:18,height:18); image.isTemplate = true
            image.accessibilityDescription = "OpenAI"; return image
        }
        for app in CodexConnection.desktopApplications() {
            for name in ["chatgptTemplate@2x.png","chatgptTemplate.png"] {
                if let image = NSImage(contentsOf:app.appendingPathComponent("Contents/Resources/"+name)) {
                    image.size = NSSize(width:18,height:18); image.isTemplate = true
                    image.accessibilityDescription = "OpenAI"; return image
                }
            }
        }
        return nil
    }()

    static var application: NSImage? {NSImage(contentsOf:Paths.resources.appendingPathComponent("BailongPet.icns"))}
    // 源图已离线清理并裁到可见边界；仅保留 2× 小图，托盘和设置共用。
    static let petTemplate: NSImage? = {
        let url = Paths.resources.appendingPathComponent("pet-status-template.png")
        guard let source = NSImage(contentsOf:url),
              let context = CGContext(data:nil,width:36,height:36,bitsPerComponent:8,bytesPerRow:144,
                                      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),
              let sourceImage = source.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
            NSLog("无法读取桌宠模板图：%@",url.path); return nil
        }
        let scale = min(36/CGFloat(sourceImage.width),36/CGFloat(sourceImage.height))
        let size = CGSize(width:CGFloat(sourceImage.width)*scale,height:CGFloat(sourceImage.height)*scale)
        let fitted = CGRect(x:(36-size.width)/2,y:(36-size.height)/2,width:size.width,height:size.height)
        context.interpolationQuality = .high
        context.draw(sourceImage,in:fitted)
        guard let raster = context.makeImage() else {NSLog("无法绘制桌宠模板图"); return nil}
        let image = NSImage(cgImage:raster,size:NSSize(width:18,height:18))
        image.isTemplate = true; image.accessibilityDescription = PetPreferences.shared.appName
        return image
    }()
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
