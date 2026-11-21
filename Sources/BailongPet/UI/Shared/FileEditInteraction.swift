import AppKit

// 正文文件行仍由 TextKit 排版，选择和菜单只读取可见文件行的元数据。
final class FileEditInteraction:NSResponder {
    private struct Row:Equatable {
        let sectionID:String
        let path:String
        let range:NSRange
    }
    private weak var view:NSTextView?
    private let baseDirectory:() -> URL?
    private var hasRows = true
    private var hovered:Row?
    private var selected:Row?
    private lazy var forceClick = WorkspaceFileForceClick(target:self,action:#selector(showForceClickMenu(_:)))

    init(view:NSTextView,baseDirectory:@escaping () -> URL?) {
        self.view = view; self.baseDirectory = baseDirectory
        super.init()
        view.addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.mouseMoved,.activeAlways,.inVisibleRect],
                                            owner:self,userInfo:nil))
        forceClick.canOpenMenu = { [weak self] event in self?.hit(event) != nil }
        view.addGestureRecognizer(forceClick)
    }
    required init?(coder:NSCoder) {fatalError()}

    func contentChanged(hasRows:Bool,reset:Bool) {
        self.hasRows = hasRows; forceClick.isEnabled = hasRows
        hovered = nil
        if let selected,!reset,hasRows,let storage = view?.textStorage,
           let row = row(at:selected.range.location,in:storage)?.row,
           row.sectionID == selected.sectionID,row.path == selected.path {
            self.selected = row
        } else {
            selected = nil
        }
    }

    func handleClick(_ event:NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.control) else {return false}
        let row = hit(event)?.row
        select(row)
        guard let row else {return false}
        if event.clickCount == 2 {Self.reveal(row.path,relativeTo:baseDirectory())}
        return true
    }

    func menu(for event:NSEvent) -> NSMenu? {
        guard let hit = hit(event) else {return nil}
        select(hit.row)
        let path = hit.row.path, directory = baseDirectory(), edits = hit.section.edits
        return WorkspaceFileMenu.make(path:Self.fileURL(path,relativeTo:directory)?.path ?? path,
                                      reveal:{Self.reveal(path,relativeTo:directory)}) {
            edits.map {Self.fileURL($0.path,relativeTo:directory)?.path ?? $0.path}
        }
    }
    @objc private func showForceClickMenu(_ gesture:WorkspaceFileForceClick) {
        guard let view,let event = gesture.mouseDownEvent,let menu = menu(for:event) else {return}
        NSMenu.popUpContextMenu(menu,with:event,for:view)
    }

    override func mouseMoved(with event:NSEvent) {updateHover(hit(event)?.row)}
    override func mouseEntered(with event:NSEvent) {updateHover(hit(event)?.row)}
    override func mouseExited(with event:NSEvent) {updateHover(nil)}

    func drawBackground(in dirtyRect:NSRect) {
        guard hasRows,let view else {return}
        if let hovered,hovered != selected,let rect = rect(for:hovered),rect.intersects(dirtyRect) {
            WorkspaceFileHighlight.draw(rect,selected:false,emphasized:false,appearance:view.effectiveAppearance)
        }
        if let selected,let rect = rect(for:selected),rect.intersects(dirtyRect) {
            WorkspaceFileHighlight.draw(rect,selected:true,emphasized:view.window?.isKeyWindow == true,appearance:view.effectiveAppearance)
        }
    }

    private func select(_ row:Row?) {
        guard let view else {return}
        if row != nil,view.selectedRange().length > 0 {
            view.setSelectedRange(NSRange(location:view.selectedRange().location,length:0))
        }
        guard selected != row else {return}
        if let selected,let rect = rect(for:selected) {view.setNeedsDisplay(rect)}
        selected = row
        if let row,let rect = rect(for:row) {view.setNeedsDisplay(rect)}
    }
    private func updateHover(_ row:Row?) {
        guard hovered != row,let view else {return}
        if let hovered,let rect = rect(for:hovered) {view.setNeedsDisplay(rect)}
        hovered = row
        if let row,let rect = rect(for:row) {view.setNeedsDisplay(rect)}
    }

    private func hit(_ event:NSEvent) -> (row:Row,section:FileEditSection)? {
        guard hasRows,let view,let manager = view.layoutManager,let container = view.textContainer,
              let storage = view.textStorage,storage.length > 0 else {return nil}
        let point = view.convert(event.locationInWindow,from:nil)
        guard view.visibleRect.contains(point) else {return nil}
        let origin = view.textContainerOrigin
        let location = NSPoint(x:point.x-origin.x,y:point.y-origin.y)
        let glyph = manager.glyphIndex(for:location,in:container)
        guard glyph < manager.numberOfGlyphs,
              let hit = row(at:manager.characterIndexForGlyph(at:glyph),in:storage),
              rect(for:hit.row)?.contains(point) == true else {return nil}
        return hit
    }
    private func row(at offset:Int,in storage:NSTextStorage) -> (row:Row,section:FileEditSection)? {
        guard offset < storage.length,
              let index = storage.attribute(.fileEditRow,at:offset,effectiveRange:nil) as? Int,
              let section = storage.attribute(.fileEditSection,at:offset,effectiveRange:nil) as? FileEditSection,
              section.edits.indices.contains(index) else {return nil}
        var range = NSRange()
        storage.attribute(.fileEditRow,at:offset,longestEffectiveRange:&range,in:NSRange(location:0,length:storage.length))
        return (Row(sectionID:section.id,path:section.edits[index].path,range:range),section)
    }
    private func rect(for row:Row) -> NSRect? {
        guard let view,let manager = view.layoutManager,let container = view.textContainer,
              let storage = view.textStorage,NSMaxRange(row.range) <= storage.length else {return nil}
        manager.ensureLayout(forCharacterRange:row.range)
        let glyphs = manager.glyphRange(forCharacterRange:row.range,actualCharacterRange:nil)
        var band = NSRect.null
        manager.enumerateLineFragments(forGlyphRange:glyphs) {line,_,_,_,_ in band = band.union(line)}
        guard !band.isEmpty else {return nil}
        let origin = view.textContainerOrigin, padding = container.lineFragmentPadding
        return NSRect(x:origin.x+padding,y:origin.y+band.minY,
                      width:container.containerSize.width-2*padding,height:band.height).intersection(view.bounds)
    }

    private static func fileURL(_ path:String,relativeTo directory:URL?) -> URL? {
        let path = (path as NSString).expandingTildeInPath
        if path.hasPrefix("/") {return URL(fileURLWithPath:path).standardizedFileURL}
        return directory?.appendingPathComponent(path).standardizedFileURL
    }
    private static func reveal(_ path:String,relativeTo directory:URL?) {
        if let file = fileURL(path,relativeTo:directory) {WorkspaceFileMenu.reveal(file)}
        else if let link = MessageFileLink.url(forPath:path) {_ = MessageFileLink.reveal(link,relativeTo:directory)}
    }
}
