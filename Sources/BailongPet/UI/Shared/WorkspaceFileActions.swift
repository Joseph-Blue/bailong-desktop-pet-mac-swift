import AppKit

enum WorkspaceFileHighlight {
    static func draw(_ rect:NSRect,selected:Bool,emphasized:Bool,appearance:NSAppearance) {
        let color = selected ? AppAccent.selectionColor(for:appearance).withAlphaComponent(emphasized ? 0.22 : 0.12)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.10)
        color.setFill()
        NSBezierPath(roundedRect:rect.insetBy(dx:2,dy:1),xRadius:5,yRadius:5).fill()
    }
}

final class WorkspaceFileForceClick:NSGestureRecognizer,NSGestureRecognizerDelegate {
    private(set) var mouseDownEvent:NSEvent?
    var canOpenMenu:(NSEvent) -> Bool = {_ in false}

    override init(target:Any?,action:Selector?) {
        super.init(target:target,action:action)
        pressureConfiguration = NSPressureConfiguration(pressureBehavior:.primaryDeepClick)
        delaysPrimaryMouseButtonEvents = true
        delegate = self
    }
    required init?(coder:NSCoder) {fatalError()}
    func gestureRecognizer(_ gestureRecognizer:NSGestureRecognizer,shouldAttemptToRecognizeWith event:NSEvent) -> Bool {
        event.type == .leftMouseDown && !event.modifierFlags.contains(.control)
            && event.associatedEventsMask.contains(.pressure) && canOpenMenu(event)
    }
    override func mouseDown(with event:NSEvent) {
        super.mouseDown(with:event)
        mouseDownEvent = event
    }
    override func pressureChange(with event:NSEvent) {
        super.pressureChange(with:event)
        if mouseDownEvent != nil,state == .possible,event.stage == 2 {state = .recognized}
    }
    override func mouseDragged(with event:NSEvent) {
        super.mouseDragged(with:event)
        if state == .possible {state = .failed}
    }
    override func mouseUp(with event:NSEvent) {
        super.mouseUp(with:event)
        if state == .possible {state = .failed}
    }
    @available(macOS 26.0, *)
    override func mouseCancelled(with event:NSEvent) {
        super.mouseCancelled(with:event)
        if state == .possible {state = .failed}
    }
    override func reset() {
        super.reset()
        mouseDownEvent = nil
    }
    override func location(in view:NSView?) -> NSPoint {
        guard let point = mouseDownEvent?.locationInWindow else {return .zero}
        return view?.convert(point,from:nil) ?? point
    }
}

enum WorkspaceFileMenu {
    static func make(path:String?,reveal:(() -> Void)?,groupPaths:(() -> [String])? = nil,allPaths:@escaping () -> [String]) -> NSMenu {
        let menu = NSMenu()
        if let path {
            if let reveal {
                let item = MenuAction(L10n.text(.workspace,"workspaceFileActions.make.menuItem"),reveal)
                let finder = AppIcons.finder.copy() as! NSImage; finder.size = NSSize(width:16,height:16)
                item.image = finder; menu.addItem(item)
            }
            menu.addItem(MenuAction(L10n.text(.workspace,"workspaceFileActions.make.menuItem.2"),symbol:"doc.on.doc") {copyPaths(path)})
            menu.addItem(.separator())
        }
        if let groupPaths {
            menu.addItem(MenuAction(L10n.text(.workspace,"workspaceFileActions.make.menuItem.3"),symbol:"doc.on.clipboard") {copyFilePaths(groupPaths())})
        }
        menu.addItem(MenuAction(L10n.text(.workspace,"workspaceFileActions.make.menuItem.4"),symbol:"list.bullet.clipboard") {copyFilePaths(allPaths())})
        menu.showProvidedImages()
        return menu
    }
    static func reveal(_ file:URL) {
        if FileManager.default.fileExists(atPath:file.path) {FinderFileReveal.reveal(file)}
        else {FinderFileReveal.openDirectory(file.deletingLastPathComponent())}
    }
    private static func copyFilePaths(_ paths:[String]) {
        var seen = Set<String>()
        copyPaths(paths.filter {seen.insert($0).inserted}.joined(separator:"\n"))
    }
    private static func copyPaths(_ text:String) {
        guard !text.isEmpty else {return}
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text,forType:.string)
    }
}
