import AppKit

enum AppIcons {
    static var quotaSymbol:String {
        if #available(macOS 15.0, *) {return "dollarsign.gauge.chart.leftthird.topthird.rightthird"}
        return "dollarsign"
    }

    private static let providerIconsURL = Bundle.main.bundleURL.pathExtension == "app"
        ? Paths.resources : Paths.project.appendingPathComponent("Assets/ProviderIcons")

    // 无图标的供应商使用文字名称。
    static let deepSeek:NSImage? = bundledProviderIcon("deepseek-logo.png","DeepSeek")
    static let xai:NSImage? = bundledProviderIcon("xai-logo.png","xAI")
    static let mistral:NSImage? = bundledProviderIcon("mistral-logo.png","Mistral")
    static let kimi:NSImage? = bundledProviderIcon("kimi-logo.png","Kimi")
    static let zhipu:NSImage? = bundledProviderIcon("zhipu-logo.png",L10n.text(.app,"branding.text.3"))
    static let bailian:NSImage? = bundledProviderIcon("bailian-logo.png",L10n.text(.app,"branding.text.4"))
    static let openRouter:NSImage? = bundledProviderIcon("openrouter-logo.png","OpenRouter")
    static let groq:NSImage? = bundledProviderIcon("groq-logo.png","Groq")
    static let bedrock:NSImage? = bundledProviderIcon("bedrock-logo.png","Amazon Bedrock")
    static let vertexAI:NSImage? = bundledProviderIcon("vertexai-logo.png","Google Cloud Vertex AI")

    static func apiProvider(_ id:String?) -> NSImage? {
        switch id {
        case "openai":return openAI
        case "deepseek":return deepSeek
        case "xai":return xai
        case "mistral":return mistral
        case "kimi":return kimi
        case "zhipu":return zhipu
        case "bailian":return bailian
        case "openrouter":return openRouter
        case "groq":return groq
        case "bedrock":return bedrock
        case "gcp":return vertexAI
        default:return nil
        }
    }

    // 模板图来自 OpenAI 桌面端的 chatgptTemplate@2x.png。
    static let openAI: NSImage? = {
        if let image = bundledProviderIcon("openai-logo.png","OpenAI",template:true) {return image}
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
    private static func bundledProviderIcon(_ file:String,_ name:String,template:Bool = false) -> NSImage? {
        guard let image = NSImage(contentsOf:providerIconsURL.appendingPathComponent(file)) else {return nil}
        image.size = NSSize(width:18,height:18); image.isTemplate = template
        image.accessibilityDescription = name
        return image
    }

    static var application: NSImage? {NSImage(contentsOf:Paths.resources.appendingPathComponent("BailongPet.icns"))}
    // 托盘使用简化头像；设置与历史使用保留花饰细节的头像。
    static let petTemplate = loadPetTemplate(named:"pet-status-template.png",pixels:36)
    static let petAvatarTemplate = loadPetTemplate(named:"pet-avatar-template.png",pixels:72)
    private static func loadPetTemplate(named name:String,pixels:Int) -> NSImage? {
        let url = Paths.resources.appendingPathComponent(name)
        guard let source = NSImage(contentsOf:url),
              let context = CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:pixels*4,
                                      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),
              let sourceImage = source.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
            NSLog(L10n.text(.app,"appIcons.sourceImage.text"),url.path); return nil
        }
        let side = CGFloat(pixels)
        let scale = min(side/CGFloat(sourceImage.width),side/CGFloat(sourceImage.height))
        let size = CGSize(width:CGFloat(sourceImage.width)*scale,height:CGFloat(sourceImage.height)*scale)
        let fitted = CGRect(x:(side-size.width)/2,y:(side-size.height)/2,width:size.width,height:size.height)
        context.interpolationQuality = .high
        context.draw(sourceImage,in:fitted)
        guard let raster = context.makeImage() else {NSLog(L10n.text(.app,"appIcons.raster.text"),name); return nil}
        let image = NSImage(cgImage:raster,size:NSSize(width:18,height:18))
        image.isTemplate = true; image.accessibilityDescription = PetPreferences.shared.appName
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
        image.isTemplate = true; image.accessibilityDescription = L10n.text(.app,"branding.loadPetTemplate.accessibilityDescription")
        return image
    }()
}
