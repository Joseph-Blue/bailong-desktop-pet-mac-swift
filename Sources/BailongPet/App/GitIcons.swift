import AppKit

enum GitIcons {
    static func repository(_ kind:GitWorkspaceStatus.RepositoryKind) -> NSImage {
        switch kind {
        case .generic:return git
        case .github:return github
        case .remote:return remote
        }
    }
    private static let remote = NSImage(systemSymbolName:"network",accessibilityDescription:"其他远端仓库")!

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
}
