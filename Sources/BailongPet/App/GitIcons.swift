import AppKit

enum GitIcons {
    static func repository(_ kind:GitWorkspaceStatus.RepositoryKind) -> NSImage {
        switch kind {
        case .generic:return git
        case .github:return github
        case .gitlab:return gitlab
        case .gitee:return gitee
        case .gitea:return gitea
        case .forgejo:return forgejo
        case .huggingFace:return huggingFace
        case .remote:return remote
        }
    }
    private static let remote = NSImage(systemSymbolName:"network",accessibilityDescription:L10n.text(.workspace,"gitStatusText.remote"))!

    // Lucide git-branch: https://lucide.dev/icons/git-branch (ISC).
    // Copyright (c) 2026 Lucide Icons and Contributors.
    // SVG's 24-point geometry, round caps and joins; scaled to a native template.
    static let git:NSImage = {
        let image = NSImage(size:NSSize(width:16,height:16),flipped:true) { _ in
            let path = NSBezierPath()
            path.move(to:NSPoint(x:15,y:6))
            path.curve(to:NSPoint(x:6,y:15),controlPoint1:NSPoint(x:10.029437,y:6),controlPoint2:NSPoint(x:6,y:10.029437))
            path.line(to:NSPoint(x:6,y:3))
            path.appendOval(in:NSRect(x:15,y:3,width:6,height:6))
            path.appendOval(in:NSRect(x:3,y:15,width:6,height:6))
            let transform = AffineTransform(scale:2.0/3.0)
            path.transform(using:transform)
            path.lineWidth = 4.0/3.0; path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.black.setStroke(); path.stroke(); return true
        }
        image.isTemplate = true; image.accessibilityDescription = "Git"; return image
    }()

    // Lucide Brands github.svg: https://github.com/azirali/lucide-brands/blob/main/svg/github.svg
    // Original artwork from lucide-static v1.0.0 (ISC). See THIRD-PARTY-NOTICES.md.
    private static let github:NSImage = {
        let image = NSImage(size:NSSize(width:16,height:16),flipped:true) { _ in
            // The SVG's two circular arcs are represented by cubic curves.
            let path = NSBezierPath()
            path.move(to:NSPoint(x:15,y:22))
            path.line(to:NSPoint(x:15,y:18))
            path.curve(to:NSPoint(x:14,y:14.5),controlPoint1:NSPoint(x:15.139120,y:16.747290),controlPoint2:NSPoint(x:14.779930,y:15.490125))
            path.curve(to:NSPoint(x:20,y:9),controlPoint1:NSPoint(x:17,y:14.5),controlPoint2:NSPoint(x:20,y:12.5))
            path.curve(to:NSPoint(x:19,y:5.5),controlPoint1:NSPoint(x:20.08,y:7.75),controlPoint2:NSPoint(x:19.73,y:6.52))
            path.curve(to:NSPoint(x:19,y:2),controlPoint1:NSPoint(x:19.28,y:4.35),controlPoint2:NSPoint(x:19.28,y:3.15))
            path.curve(to:NSPoint(x:16,y:3.5),controlPoint1:NSPoint(x:19,y:2),controlPoint2:NSPoint(x:18,y:2))
            path.curve(to:NSPoint(x:8,y:3.5),controlPoint1:NSPoint(x:13.36,y:3),controlPoint2:NSPoint(x:10.64,y:3))
            path.curve(to:NSPoint(x:5,y:2),controlPoint1:NSPoint(x:6,y:2),controlPoint2:NSPoint(x:5,y:2))
            path.curve(to:NSPoint(x:5,y:5.5),controlPoint1:NSPoint(x:4.7,y:3.15),controlPoint2:NSPoint(x:4.7,y:4.35))
            path.curve(to:NSPoint(x:4,y:9),controlPoint1:NSPoint(x:4.271873,y:6.515884),controlPoint2:NSPoint(x:3.918472,y:7.752787))
            path.curve(to:NSPoint(x:10,y:14.5),controlPoint1:NSPoint(x:4,y:12.5),controlPoint2:NSPoint(x:7,y:14.5))
            path.curve(to:NSPoint(x:9.15,y:16.15),controlPoint1:NSPoint(x:9.61,y:14.99),controlPoint2:NSPoint(x:9.32,y:15.55))
            path.curve(to:NSPoint(x:9,y:18),controlPoint1:NSPoint(x:8.98,y:16.75),controlPoint2:NSPoint(x:8.93,y:17.38))
            path.line(to:NSPoint(x:9,y:22))
            path.move(to:NSPoint(x:9,y:18))
            path.curve(to:NSPoint(x:2,y:16),controlPoint1:NSPoint(x:4.49,y:20),controlPoint2:NSPoint(x:4,y:16))
            path.transform(using:AffineTransform(scale:2.0/3.0))
            path.lineWidth = 4.0/3.0
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "GitHub"
        return image
    }()

    // Geometry uses the upstream viewBox and is compiled into template images.
    private static func template(_ title:String, viewBox:CGFloat = 24, inset:CGFloat = 0, strokeWidth:CGFloat? = nil,
                                 draw:(CGMutablePath) -> Void) -> NSImage {
        let path = CGMutablePath()
        draw(path)
        let image = NSImage(size:NSSize(width:16,height:16),flipped:true) { _ in
            let context = NSGraphicsContext.current!.cgContext
            let scale = (24-2*inset)/viewBox * 2/3
            context.saveGState()
            context.translateBy(x:inset*2/3,y:inset*2/3)
            context.scaleBy(x:scale,y:scale)
            context.addPath(path)
            if let strokeWidth {
                context.setLineWidth(strokeWidth)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setStrokeColor(NSColor.black.cgColor)
                context.strokePath()
            } else {
                context.setFillColor(NSColor.black.cgColor)
                context.fillPath()
            }
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = title
        return image
    }

    // Lucide Brands · gitlab.svg (ISC).
    private static let gitlab = template("GitLab", strokeWidth:2) { path in
        path.move(to:CGPoint(x:22,y:13.29))
        path.addLine(to:CGPoint(x:18.67,y:3.29))
        path.addCurve(to:CGPoint(x:18.53,y:3.11),control1:CGPoint(x:18.6408,y:3.2182),control2:CGPoint(x:18.5924,y:3.1559))
        path.addCurve(to:CGPoint(x:18.31,y:3),control1:CGPoint(x:18.4709,y:3.05),control2:CGPoint(x:18.3935,y:3.0113))
        path.addCurve(to:CGPoint(x:18.08,y:3.07),control1:CGPoint(x:18.2279,y:2.9985),control2:CGPoint(x:18.1474,y:3.023))
        path.addCurve(to:CGPoint(x:17.94,y:3.25),control1:CGPoint(x:18.0176,y:3.1159),control2:CGPoint(x:17.9692,y:3.1782))
        path.addLine(to:CGPoint(x:15.68,y:9.92))
        path.addLine(to:CGPoint(x:8.32,y:9.92))
        path.addLine(to:CGPoint(x:6.1,y:3.26))
        path.addCurve(to:CGPoint(x:6,y:3.08),control1:CGPoint(x:6.0821,y:3.1926),control2:CGPoint(x:6.0478,y:3.1308))
        path.addCurve(to:CGPoint(x:5.74,y:3),control1:CGPoint(x:5.9262,y:3.0222),control2:CGPoint(x:5.8336,y:2.9937))
        path.addCurve(to:CGPoint(x:5.51,y:3.07),control1:CGPoint(x:5.6579,y:2.9985),control2:CGPoint(x:5.5774,y:3.023))
        path.addCurve(to:CGPoint(x:5.37,y:3.25),control1:CGPoint(x:5.4476,y:3.1159),control2:CGPoint(x:5.3992,y:3.1782))
        path.addLine(to:CGPoint(x:2,y:13.29))
        path.addCurve(to:CGPoint(x:2.27,y:14.12),control1:CGPoint(x:1.8999,y:13.5959),control2:CGPoint(x:2.0091,y:13.9315))
        path.addLine(to:CGPoint(x:12,y:21))
        path.addLine(to:CGPoint(x:21.69,y:14.12))
        path.addCurve(to:CGPoint(x:22,y:13.29),control1:CGPoint(x:21.9745,y:13.9497),control2:CGPoint(x:22.1031,y:13.6051))
        path.closeSubpath()
    }

    // Remix Icon · gitee-line.svg (Remix Icon License v1.0).
    private static let gitee = template("Gitee") { path in
        path.move(to:CGPoint(x:12,y:2))
        path.addCurve(to:CGPoint(x:22,y:12),control1:CGPoint(x:17.5228,y:2),control2:CGPoint(x:22,y:6.4771))
        path.addCurve(to:CGPoint(x:12,y:22),control1:CGPoint(x:22,y:17.5228),control2:CGPoint(x:17.5228,y:22))
        path.addCurve(to:CGPoint(x:2,y:12),control1:CGPoint(x:6.4771,y:22),control2:CGPoint(x:2,y:17.5228))
        path.addCurve(to:CGPoint(x:12,y:2),control1:CGPoint(x:2,y:6.4771),control2:CGPoint(x:6.4771,y:2))
        path.closeSubpath()
        path.move(to:CGPoint(x:12,y:4))
        path.addCurve(to:CGPoint(x:4,y:12),control1:CGPoint(x:7.5817,y:4),control2:CGPoint(x:4,y:7.5817))
        path.addCurve(to:CGPoint(x:12,y:20),control1:CGPoint(x:4,y:16.4183),control2:CGPoint(x:7.5817,y:20))
        path.addCurve(to:CGPoint(x:20,y:12),control1:CGPoint(x:16.4183,y:20),control2:CGPoint(x:20,y:16.4183))
        path.addCurve(to:CGPoint(x:12,y:4),control1:CGPoint(x:20,y:7.5817),control2:CGPoint(x:16.4183,y:4))
        path.closeSubpath()
        path.move(to:CGPoint(x:17,y:6.5))
        path.addCurve(to:CGPoint(x:17.5,y:7),control1:CGPoint(x:17.2761,y:6.5),control2:CGPoint(x:17.5,y:6.7239))
        path.addLine(to:CGPoint(x:17.5,y:8))
        path.addCurve(to:CGPoint(x:17,y:8.5),control1:CGPoint(x:17.5,y:8.2761),control2:CGPoint(x:17.2761,y:8.5))
        path.addLine(to:CGPoint(x:10,y:8.5))
        path.addCurve(to:CGPoint(x:8.5,y:10),control1:CGPoint(x:9.1716,y:8.5),control2:CGPoint(x:8.5,y:9.1716))
        path.addLine(to:CGPoint(x:8.5,y:15))
        path.addCurve(to:CGPoint(x:9,y:15.5),control1:CGPoint(x:8.5,y:15.2761),control2:CGPoint(x:8.7239,y:15.5))
        path.addLine(to:CGPoint(x:14,y:15.5))
        path.addCurve(to:CGPoint(x:15.5,y:14),control1:CGPoint(x:14.8284,y:15.5),control2:CGPoint(x:15.5,y:14.8284))
        path.addLine(to:CGPoint(x:15.5,y:13))
        path.addLine(to:CGPoint(x:11.5,y:13))
        path.addCurve(to:CGPoint(x:11,y:12.5),control1:CGPoint(x:11.2239,y:13),control2:CGPoint(x:11,y:12.7761))
        path.addLine(to:CGPoint(x:11,y:11.5))
        path.addCurve(to:CGPoint(x:11.5,y:11),control1:CGPoint(x:11,y:11.2239),control2:CGPoint(x:11.2239,y:11))
        path.addLine(to:CGPoint(x:17,y:11))
        path.addCurve(to:CGPoint(x:17.5,y:11.5),control1:CGPoint(x:17.2761,y:11),control2:CGPoint(x:17.5,y:11.2239))
        path.addLine(to:CGPoint(x:17.5,y:14))
        path.addCurve(to:CGPoint(x:14,y:17.5),control1:CGPoint(x:17.5,y:15.933),control2:CGPoint(x:15.933,y:17.5))
        path.addLine(to:CGPoint(x:7,y:17.5))
        path.addCurve(to:CGPoint(x:6.5,y:17),control1:CGPoint(x:6.7239,y:17.5),control2:CGPoint(x:6.5,y:17.2761))
        path.addLine(to:CGPoint(x:6.5,y:10))
        path.addCurve(to:CGPoint(x:10,y:6.5),control1:CGPoint(x:6.5,y:8.067),control2:CGPoint(x:8.067,y:6.5))
        path.addLine(to:CGPoint(x:17,y:6.5))
        path.closeSubpath()
    }

    // Icon Monks · gitea-logo.svg (MIT).
    private static let gitea = template("Gitea", viewBox:256) { path in
        path.move(to:CGPoint(x:82.34,y:50.34))
        path.addCurve(to:CGPoint(x:80,y:56),control1:CGPoint(x:80.8401,y:51.8416),control2:CGPoint(x:79.9983,y:53.8776))
        path.addLine(to:CGPoint(x:80,y:64))
        path.addLine(to:CGPoint(x:64,y:64))
        path.addCurve(to:CGPoint(x:30.7325,y:86.2223),control1:CGPoint(x:49.4368,y:63.9966),control2:CGPoint(x:36.306,y:72.7678))
        path.addCurve(to:CGPoint(x:38.54,y:125.46),control1:CGPoint(x:25.1589,y:99.6767),control2:CGPoint(x:28.2406,y:115.1639))
        path.addCurve(to:CGPoint(x:64,y:136),control1:CGPoint(x:45.293,y:132.2108),control2:CGPoint(x:54.4514,y:136.0022))
        path.addLine(to:CGPoint(x:80,y:136))
        path.addCurve(to:CGPoint(x:80.06,y:136.99),control1:CGPoint(x:79.9995,y:136.3309),control2:CGPoint(x:80.0195,y:136.6616))
        path.addQuadCurve(to:CGPoint(x:97.27,y:188.33),control:CGPoint(x:83.87,y:167.49))
        path.addQuadCurve(to:CGPoint(x:144,y:216),control:CGPoint(x:115.06,y:216))
        path.addLine(to:CGPoint(x:152,y:216))
        path.addQuadCurve(to:CGPoint(x:207.97,y:166.35),control:CGPoint(x:189.02,y:216))
        path.addQuadCurve(to:CGPoint(x:224,y:56),control:CGPoint(x:224,y:124.38))
        path.addCurve(to:CGPoint(x:216,y:48),control1:CGPoint(x:224,y:51.5817),control2:CGPoint(x:220.4183,y:48))
        path.addLine(to:CGPoint(x:88,y:48))
        path.addCurve(to:CGPoint(x:82.34,y:50.34),control1:CGPoint(x:85.8776,y:47.9983),control2:CGPoint(x:83.8416,y:48.8401))
        path.closeSubpath()
        path.move(to:CGPoint(x:207.94,y:64))
        path.addQuadCurve(to:CGPoint(x:193.03,y:160.65),control:CGPoint(x:207.07,y:123.86))
        path.addQuadCurve(to:CGPoint(x:152,y:200),control:CGPoint(x:178,y:200))
        path.addLine(to:CGPoint(x:144,y:200))
        path.addQuadCurve(to:CGPoint(x:110.73,y:179.67),control:CGPoint(x:123.8,y:200))
        path.addQuadCurve(to:CGPoint(x:96,y:135.5),control:CGPoint(x:99.4,y:162.05))
        path.addLine(to:CGPoint(x:96,y:133.29))
        path.addCurve(to:CGPoint(x:96,y:122.71),control1:CGPoint(x:98.6693,y:130.2684),control2:CGPoint(x:98.6693,y:125.7316))
        path.addLine(to:CGPoint(x:96,y:64))
        path.addLine(to:CGPoint(x:207.94,y:64))
        path.closeSubpath()
        path.move(to:CGPoint(x:64,y:120))
        path.addCurve(to:CGPoint(x:45.5264,y:107.6531),control1:CGPoint(x:55.9121,y:119.9983),control2:CGPoint(x:48.6213,y:115.1254))
        path.addCurve(to:CGPoint(x:49.86,y:85.86),control1:CGPoint(x:42.4316,y:100.1807),control2:CGPoint(x:44.1418,y:91.5799))
        path.addCurve(to:CGPoint(x:64,y:80),control1:CGPoint(x:53.6099,y:82.109),control2:CGPoint(x:58.6961,y:80.0011))
        path.addLine(to:CGPoint(x:80,y:80))
        path.addLine(to:CGPoint(x:80,y:120))
        path.addLine(to:CGPoint(x:64,y:120))
        path.closeSubpath()
        path.move(to:CGPoint(x:152,y:96))
        path.addCurve(to:CGPoint(x:146.34,y:98.34),control1:CGPoint(x:149.8776,y:95.9983),control2:CGPoint(x:147.8416,y:96.8401))
        path.addLine(to:CGPoint(x:114.34,y:130.34))
        path.addCurve(to:CGPoint(x:111.9937,y:136),control1:CGPoint(x:112.8378,y:131.8405),control2:CGPoint(x:111.9937,y:133.8767))
        path.addCurve(to:CGPoint(x:114.34,y:141.66),control1:CGPoint(x:111.9937,y:138.1233),control2:CGPoint(x:112.8378,y:140.1595))
        path.addLine(to:CGPoint(x:146.34,y:173.66))
        path.addCurve(to:CGPoint(x:152,y:176.0063),control1:CGPoint(x:147.8405,y:175.1622),control2:CGPoint(x:149.8767,y:176.0063))
        path.addCurve(to:CGPoint(x:157.66,y:173.66),control1:CGPoint(x:154.1233,y:176.0063),control2:CGPoint(x:156.1595,y:175.1622))
        path.addLine(to:CGPoint(x:189.66,y:141.66))
        path.addCurve(to:CGPoint(x:192.0063,y:136),control1:CGPoint(x:191.1622,y:140.1595),control2:CGPoint(x:192.0063,y:138.1233))
        path.addCurve(to:CGPoint(x:189.66,y:130.34),control1:CGPoint(x:192.0063,y:133.8767),control2:CGPoint(x:191.1622,y:131.8405))
        path.addLine(to:CGPoint(x:157.66,y:98.34))
        path.addCurve(to:CGPoint(x:152,y:96),control1:CGPoint(x:156.1584,y:96.8401),control2:CGPoint(x:154.1224,y:95.9983))
        path.closeSubpath()
        path.move(to:CGPoint(x:131.31,y:136))
        path.addLine(to:CGPoint(x:152,y:115.31))
        path.addLine(to:CGPoint(x:172.69,y:136))
        path.addLine(to:CGPoint(x:152,y:156.69))
        path.addLine(to:CGPoint(x:131.31,y:136))
        path.closeSubpath()
    }

    // Forgejo monochrome mark by Caesar Schinas (CC BY-SA 4.0), via Simple Icons. Adapted to an inset AppKit path.
    private static let forgejo = template("Forgejo", inset:2) { path in
        path.move(to:CGPoint(x:16.7773,y:0))
        path.addCurve(to:CGPoint(x:19.6777,y:2.9005),control1:CGPoint(x:18.3791,y:0),control2:CGPoint(x:19.6777,y:1.2986))
        path.addCurve(to:CGPoint(x:16.7773,y:5.8009),control1:CGPoint(x:19.6777,y:4.5024),control2:CGPoint(x:18.3791,y:5.8009))
        path.addCurve(to:CGPoint(x:14.2485,y:4.3222),control1:CGPoint(x:15.6919,y:5.8009),control2:CGPoint(x:14.7458,y:5.2049))
        path.addLine(to:CGPoint(x:12.91,y:4.3222))
        path.addCurve(to:CGPoint(x:8.6451,y:8.5172),control1:CGPoint(x:10.5778,y:4.3222),control2:CGPoint(x:8.6828,y:6.194))
        path.addLine(to:CGPoint(x:8.6444,y:10.6347))
        path.addCurve(to:CGPoint(x:12.7924,y:9.2142),control1:CGPoint(x:9.8418,y:9.734),control2:CGPoint(x:11.2942,y:9.2366))
        path.addLine(to:CGPoint(x:12.91,y:9.2132))
        path.addLine(to:CGPoint(x:14.2485,y:9.2134))
        path.addCurve(to:CGPoint(x:16.7773,y:7.7346),control1:CGPoint(x:14.7458,y:8.3307),control2:CGPoint(x:15.6919,y:7.7346))
        path.addCurve(to:CGPoint(x:19.6777,y:10.6351),control1:CGPoint(x:18.3791,y:7.7346),control2:CGPoint(x:19.6777,y:9.0332))
        path.addCurve(to:CGPoint(x:16.7773,y:13.5355),control1:CGPoint(x:19.6777,y:12.237),control2:CGPoint(x:18.3791,y:13.5355))
        path.addCurve(to:CGPoint(x:14.2485,y:12.0568),control1:CGPoint(x:15.6919,y:13.5355),control2:CGPoint(x:14.7458,y:12.9395))
        path.addLine(to:CGPoint(x:12.91,y:12.0568))
        path.addCurve(to:CGPoint(x:8.6451,y:16.2518),control1:CGPoint(x:10.5778,y:12.0568),control2:CGPoint(x:8.6828,y:13.9286))
        path.addLine(to:CGPoint(x:8.6444,y:18.5708))
        path.addCurve(to:CGPoint(x:10.1232,y:21.0995),control1:CGPoint(x:9.5271,y:19.0681),control2:CGPoint(x:10.1232,y:20.0142))
        path.addCurve(to:CGPoint(x:7.2227,y:24),control1:CGPoint(x:10.1232,y:22.7015),control2:CGPoint(x:8.8246,y:24))
        path.addCurve(to:CGPoint(x:4.3223,y:21.0995),control1:CGPoint(x:5.6209,y:24),control2:CGPoint(x:4.3223,y:22.7014))
        path.addCurve(to:CGPoint(x:5.8011,y:18.5708),control1:CGPoint(x:4.3223,y:20.0142),control2:CGPoint(x:4.9183,y:19.0681))
        path.addLine(to:CGPoint(x:5.8009,y:8.5877))
        path.addCurve(to:CGPoint(x:12.7924,y:1.4797),control1:CGPoint(x:5.8009,y:4.7007),control2:CGPoint(x:8.9204,y:1.5424))
        path.addLine(to:CGPoint(x:12.91,y:1.4787))
        path.addLine(to:CGPoint(x:14.2485,y:1.4787))
        path.addCurve(to:CGPoint(x:16.7773,y:0),control1:CGPoint(x:14.7458,y:0.5962),control2:CGPoint(x:15.692,y:0))
        path.closeSubpath()
        path.move(to:CGPoint(x:7.2227,y:19.9052))
        path.addCurve(to:CGPoint(x:6.0284,y:21.0995),control1:CGPoint(x:6.5631,y:19.9052),control2:CGPoint(x:6.0284,y:20.4399))
        path.addCurve(to:CGPoint(x:7.2227,y:22.2938),control1:CGPoint(x:6.0284,y:21.7591),control2:CGPoint(x:6.5631,y:22.2938))
        path.addCurve(to:CGPoint(x:8.4171,y:21.0995),control1:CGPoint(x:7.8823,y:22.2938),control2:CGPoint(x:8.4171,y:21.7591))
        path.addCurve(to:CGPoint(x:7.2227,y:19.9052),control1:CGPoint(x:8.4171,y:20.4399),control2:CGPoint(x:7.8823,y:19.9052))
        path.closeSubpath()
        path.move(to:CGPoint(x:16.7773,y:9.4408))
        path.addCurve(to:CGPoint(x:15.5829,y:10.6351),control1:CGPoint(x:16.1177,y:9.4408),control2:CGPoint(x:15.5829,y:9.9755))
        path.addCurve(to:CGPoint(x:16.7773,y:11.8294),control1:CGPoint(x:15.5829,y:11.2947),control2:CGPoint(x:16.1177,y:11.8294))
        path.addCurve(to:CGPoint(x:17.9716,y:10.6351),control1:CGPoint(x:17.4369,y:11.8294),control2:CGPoint(x:17.9716,y:11.2947))
        path.addCurve(to:CGPoint(x:16.7773,y:9.4408),control1:CGPoint(x:17.9716,y:9.9755),control2:CGPoint(x:17.4369,y:9.4408))
        path.closeSubpath()
        path.move(to:CGPoint(x:16.7773,y:1.7062))
        path.addCurve(to:CGPoint(x:15.5829,y:2.9005),control1:CGPoint(x:16.1177,y:1.7062),control2:CGPoint(x:15.5829,y:2.2409))
        path.addCurve(to:CGPoint(x:16.7773,y:4.0948),control1:CGPoint(x:15.5829,y:3.5601),control2:CGPoint(x:16.1177,y:4.0948))
        path.addCurve(to:CGPoint(x:17.9716,y:2.9005),control1:CGPoint(x:17.4369,y:4.0948),control2:CGPoint(x:17.9716,y:3.5601))
        path.addCurve(to:CGPoint(x:16.7773,y:1.7062),control1:CGPoint(x:17.9716,y:2.2409),control2:CGPoint(x:17.4369,y:1.7062))
        path.closeSubpath()
    }

    // Icon Monks · hugging-face-logo.svg (MIT).
    private static let huggingFace = template("Hugging Face", viewBox:256) { path in
        path.move(to:CGPoint(x:27,y:183))
        path.addCurve(to:CGPoint(x:33.22,y:204.24),control1:CGPoint(x:27.0441,y:190.5227),control2:CGPoint(x:29.1992,y:197.8819))
        path.addCurve(to:CGPoint(x:34.34,y:205.66),control1:CGPoint(x:33.5385,y:204.7541),control2:CGPoint(x:33.9142,y:205.2305))
        path.addQuadCurve(to:CGPoint(x:63.2,y:217.96),control:CGPoint(x:44.81,y:216.12))
        path.addQuadCurve(to:CGPoint(x:98.16,y:206.86),control:CGPoint(x:82.7,y:219.91))
        path.addCurve(to:CGPoint(x:109.64,y:191.4),control1:CGPoint(x:103.1716,y:202.7024),control2:CGPoint(x:107.1092,y:197.3998))
        path.addCurve(to:CGPoint(x:111.31,y:168.12),control1:CGPoint(x:112.7173,y:184.029),control2:CGPoint(x:113.3037,y:175.8548))
        path.addQuadCurve(to:CGPoint(x:128,y:172),control:CGPoint(x:118.66,y:172))
        path.addQuadCurve(to:CGPoint(x:144.69,y:168.12),control:CGPoint(x:137.34,y:172))
        path.addCurve(to:CGPoint(x:146.36,y:191.4),control1:CGPoint(x:142.703,y:175.8554),control2:CGPoint(x:143.2892,y:184.0275))
        path.addCurve(to:CGPoint(x:157.84,y:206.86),control1:CGPoint(x:148.8963,y:197.3966),control2:CGPoint(x:152.8329,y:202.6981))
        path.addQuadCurve(to:CGPoint(x:192.8,y:217.96),control:CGPoint(x:173.3,y:219.91))
        path.addQuadCurve(to:CGPoint(x:221.66,y:205.66),control:CGPoint(x:211.19,y:216.12))
        path.addCurve(to:CGPoint(x:222.78,y:204.24),control1:CGPoint(x:222.0858,y:205.2305),control2:CGPoint(x:222.4615,y:204.7541))
        path.addCurve(to:CGPoint(x:229,y:183),control1:CGPoint(x:226.8067,y:197.8846),control2:CGPoint(x:228.9624,y:190.5236))
        path.addCurve(to:CGPoint(x:222.43,y:160.06),control1:CGPoint(x:228.9633,y:174.8944),control2:CGPoint(x:226.6898,y:166.9561))
        path.addCurve(to:CGPoint(x:211.46,y:147.77),control1:CGPoint(x:219.5505,y:155.3308),control2:CGPoint(x:215.8331,y:151.166))
        path.addQuadCurve(to:CGPoint(x:214.73,y:104.64),control:CGPoint(x:218.6,y:127.21))
        path.addCurve(to:CGPoint(x:128,y:31.5365),control1:CGPoint(x:207.4759,y:62.4052),control2:CGPoint(x:170.8532,y:31.5365))
        path.addCurve(to:CGPoint(x:41.27,y:104.64),control1:CGPoint(x:85.1468,y:31.5365),control2:CGPoint(x:48.5241,y:62.4052))
        path.addQuadCurve(to:CGPoint(x:44.54,y:147.77),control:CGPoint(x:37.4,y:127.21))
        path.addCurve(to:CGPoint(x:33.57,y:160.06),control1:CGPoint(x:40.1675,y:151.1667),control2:CGPoint(x:36.4502,y:155.3313))
        path.addCurve(to:CGPoint(x:27,y:183),control1:CGPoint(x:29.3054,y:166.954),control2:CGPoint(x:27.0315,y:174.8936))
        path.closeSubpath()
        path.move(to:CGPoint(x:81.59,y:64.47))
        path.addCurve(to:CGPoint(x:152.6996,y:51.8887),control1:CGPoint(x:101.3245,y:47.8333),control2:CGPoint(x:128.4548,y:43.0331))
        path.addCurve(to:CGPoint(x:198.96,y:107.34),control1:CGPoint(x:176.9445,y:60.7442),control2:CGPoint(x:194.5941,y:81.9004))
        path.addQuadCurve(to:CGPoint(x:197.11,y:140.12),control:CGPoint(x:201.89,y:124.43))
        path.addCurve(to:CGPoint(x:185,y:138),control1:CGPoint(x:193.217,y:138.7535),control2:CGPoint(x:189.1257,y:138.0373))
        path.addCurve(to:CGPoint(x:162.57,y:144.47),control1:CGPoint(x:177.0611,y:137.9861),control2:CGPoint(x:169.2819,y:140.23))
        path.addCurve(to:CGPoint(x:164,y:132),control1:CGPoint(x:163.5525,y:140.387),control2:CGPoint(x:164.0327,y:136.1994))
        path.addCurve(to:CGPoint(x:156,y:124),control1:CGPoint(x:164,y:127.5817),control2:CGPoint(x:160.4183,y:124))
        path.addLine(to:CGPoint(x:100,y:124))
        path.addCurve(to:CGPoint(x:92,y:132),control1:CGPoint(x:95.5817,y:124),control2:CGPoint(x:92,y:127.5817))
        path.addCurve(to:CGPoint(x:93.43,y:144.47),control1:CGPoint(x:91.9664,y:136.1994),control2:CGPoint(x:92.4466,y:140.3872))
        path.addCurve(to:CGPoint(x:71,y:138),control1:CGPoint(x:86.7172,y:140.232),control2:CGPoint(x:78.9386,y:137.9883))
        path.addCurve(to:CGPoint(x:58.89,y:140.12),control1:CGPoint(x:66.8745,y:138.0395),control2:CGPoint(x:62.7835,y:138.7556))
        path.addQuadCurve(to:CGPoint(x:57.04,y:107.34),control:CGPoint(x:54.11,y:124.43))
        path.addCurve(to:CGPoint(x:81.59,y:64.47),control1:CGPoint(x:59.9114,y:90.6019),control2:CGPoint(x:68.6069,y:75.4175))
        path.closeSubpath()
        path.move(to:CGPoint(x:100,y:89.5))
        path.addCurve(to:CGPoint(x:89.5,y:100),control1:CGPoint(x:94.2,y:89.5),control2:CGPoint(x:89.5,y:94.2))
        path.addCurve(to:CGPoint(x:100,y:110.5),control1:CGPoint(x:89.5,y:105.8),control2:CGPoint(x:94.2,y:110.5))
        path.addCurve(to:CGPoint(x:110.5,y:100),control1:CGPoint(x:105.8,y:110.5),control2:CGPoint(x:110.5,y:105.8))
        path.addCurve(to:CGPoint(x:100,y:89.5),control1:CGPoint(x:110.5,y:94.2),control2:CGPoint(x:105.8,y:89.5))
        path.closeSubpath()
        path.move(to:CGPoint(x:156,y:89.5))
        path.addCurve(to:CGPoint(x:145.5,y:100),control1:CGPoint(x:150.2,y:89.5),control2:CGPoint(x:145.5,y:94.2))
        path.addCurve(to:CGPoint(x:156,y:110.5),control1:CGPoint(x:145.5,y:105.8),control2:CGPoint(x:150.2,y:110.5))
        path.addCurve(to:CGPoint(x:166.5,y:100),control1:CGPoint(x:161.8,y:110.5),control2:CGPoint(x:166.5,y:105.8))
        path.addCurve(to:CGPoint(x:156,y:89.5),control1:CGPoint(x:166.5,y:94.2),control2:CGPoint(x:161.8,y:89.5))
        path.closeSubpath()
        path.move(to:CGPoint(x:113.92,y:150.12))
        path.addCurve(to:CGPoint(x:108.83,y:140),control1:CGPoint(x:111.3858,y:147.2375),control2:CGPoint(x:109.6333,y:143.7531))
        path.addLine(to:CGPoint(x:147.16,y:140))
        path.addCurve(to:CGPoint(x:142.08,y:150.12),control1:CGPoint(x:146.3677,y:143.755),control2:CGPoint(x:144.6177,y:147.2412))
        path.addQuadCurve(to:CGPoint(x:128,y:156),control:CGPoint(x:136.73,y:156))
        path.addQuadCurve(to:CGPoint(x:113.92,y:150.12),control:CGPoint(x:119.27,y:156))
        path.closeSubpath()
        path.move(to:CGPoint(x:54.17,y:166.38))
        path.addCurve(to:CGPoint(x:64.3203,y:165.9844),control1:CGPoint(x:57.2139,y:168.6886),control2:CGPoint(x:61.4653,y:168.5229))
        path.addCurve(to:CGPoint(x:65.9,y:155.95),control1:CGPoint(x:67.1752,y:163.4458),control2:CGPoint(x:67.8369,y:159.2429))
        path.addCurve(to:CGPoint(x:65.28,y:154.87),control1:CGPoint(x:65.6906,y:155.5916),control2:CGPoint(x:65.4839,y:155.2316))
        path.addCurve(to:CGPoint(x:71,y:154),control1:CGPoint(x:67.1362,y:154.3122),control2:CGPoint(x:69.0619,y:154.0193))
        path.addCurve(to:CGPoint(x:87.26,y:159.67),control1:CGPoint(x:76.8989,y:154.034),control2:CGPoint(x:82.619,y:156.0287))
        path.addQuadCurve(to:CGPoint(x:96.13,y:173.44),control:CGPoint(x:94.45,y:165.25))
        path.addQuadCurve(to:CGPoint(x:87.84,y:194.64),control:CGPoint(x:98.15,y:185.94))
        path.addQuadCurve(to:CGPoint(x:64.8,y:202.04),control:CGPoint(x:77.55,y:203.32))
        path.addQuadCurve(to:CGPoint(x:46.3,y:194.96),control:CGPoint(x:52.71,y:200.83))
        path.addCurve(to:CGPoint(x:43,y:183),control1:CGPoint(x:44.1633,y:191.3346),control2:CGPoint(x:43.0247,y:187.2081))
        path.addCurve(to:CGPoint(x:47.21,y:168.41),control1:CGPoint(x:43.0342,y:177.8419),control2:CGPoint(x:44.4909,y:172.7933))
        path.addCurve(to:CGPoint(x:51.47,y:162.97),control1:CGPoint(x:48.415,y:166.4381),control2:CGPoint(x:49.8445,y:164.6126))
        path.addCurve(to:CGPoint(x:52.1,y:164.05),control1:CGPoint(x:51.6777,y:163.3313),control2:CGPoint(x:51.8877,y:163.6913))
        path.addCurve(to:CGPoint(x:54.17,y:166.38),control1:CGPoint(x:52.6306,y:164.9549),control2:CGPoint(x:53.3339,y:165.7466))
        path.closeSubpath()
        path.move(to:CGPoint(x:189.08,y:158.9))
        path.addCurve(to:CGPoint(x:194.379,y:167.5498),control1:CGPoint(x:188.5589,y:162.6777),control2:CGPoint(x:190.7768,y:166.298))
        path.addCurve(to:CGPoint(x:203.9,y:164.05),control1:CGPoint(x:197.9812,y:168.8016),control2:CGPoint(x:201.9661,y:167.3368))
        path.addCurve(to:CGPoint(x:204.53,y:162.97),control1:CGPoint(x:204.1123,y:163.6913),control2:CGPoint(x:204.3223,y:163.3313))
        path.addCurve(to:CGPoint(x:208.79,y:168.41),control1:CGPoint(x:206.1554,y:164.6127),control2:CGPoint(x:207.5849,y:166.4382))
        path.addCurve(to:CGPoint(x:213,y:183),control1:CGPoint(x:211.5138,y:172.7912),control2:CGPoint(x:212.971,y:177.8412))
        path.addCurve(to:CGPoint(x:209.7,y:194.96),control1:CGPoint(x:212.9711,y:187.2075),control2:CGPoint(x:211.8328,y:191.333))
        path.addQuadCurve(to:CGPoint(x:191.2,y:202.04),control:CGPoint(x:203.29,y:200.83))
        path.addQuadCurve(to:CGPoint(x:168.16,y:194.64),control:CGPoint(x:178.45,y:203.32))
        path.addQuadCurve(to:CGPoint(x:159.87,y:173.44),control:CGPoint(x:157.85,y:185.94))
        path.addQuadCurve(to:CGPoint(x:168.74,y:159.67),control:CGPoint(x:161.55,y:165.25))
        path.addCurve(to:CGPoint(x:185,y:154),control1:CGPoint(x:173.3777,y:156.0226),control2:CGPoint(x:179.0999,y:154.0272))
        path.addCurve(to:CGPoint(x:190.72,y:154.87),control1:CGPoint(x:186.938,y:154.0201),control2:CGPoint(x:188.8636,y:154.313))
        path.addCurve(to:CGPoint(x:190.1,y:155.95),control1:CGPoint(x:190.5161,y:155.2316),control2:CGPoint(x:190.3094,y:155.5916))
        path.addCurve(to:CGPoint(x:189.08,y:158.9),control1:CGPoint(x:189.5696,y:156.8568),control2:CGPoint(x:189.223,y:157.8592))
        path.closeSubpath()
    }
}
