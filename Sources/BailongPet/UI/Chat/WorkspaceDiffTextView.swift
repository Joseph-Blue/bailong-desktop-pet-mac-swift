import AppKit
import CoreText

enum WorkspaceDiffSide {
    case inline, before, after

    func lineNumber(for line:WorkspaceDiffPatch.Line) -> Int? {
        switch self {
        case .inline:return line.new ?? line.old
        case .before:return line.old
        case .after:return line.new
        }
    }
}

final class WorkspaceDiffTextView:AppTextView {
    enum Band {
        case code(WorkspaceDiffPatch.Line), context, detail, spacer

        var fill:NSColor? {
            switch self {
            case .code(let line):
                switch line.kind {
                case .addition:return NSColor.systemGreen.withAlphaComponent(0.13)
                case .deletion:return NSColor.systemRed.withAlphaComponent(0.13)
                default:return nil
                }
            case .context:return NSColor.secondaryLabelColor.withAlphaComponent(0.10)
            case .detail:return nil
            case .spacer:return NSColor.secondaryLabelColor.withAlphaComponent(0.06)
            }
        }
    }
    var bands = [Int:Band]()

    override func draw(_ rect:NSRect) {
        visitBands(in:rect) {band,row,_ in
            guard let color = band.fill else {return}
            color.setFill()
            NSRect(x:rect.minX,y:row.minY,width:rect.width,height:row.height).fill()
        }
        super.draw(rect)
    }

    func visitBands(in rect:NSRect,_ visit:@escaping (Band,NSRect,CGFloat) -> Void) {
        guard let manager = layoutManager,let container = textContainer,!bands.isEmpty else {return}
        let origin = textContainerOrigin
        let area = NSRect(x:0,y:rect.minY-origin.y,width:max(1,bounds.width),height:rect.height)
        let glyphs = manager.glyphRange(forBoundingRect:area,in:container)
        manager.enumerateLineFragments(forGlyphRange:glyphs) {line,_,_,range,_ in
            let offset = manager.characterIndexForGlyph(at:range.location)
            guard let band = self.bands[offset] else {return}
            let frame = line.offsetBy(dx:origin.x,dy:origin.y)
            let baseline = frame.minY+manager.location(forGlyphAt:range.location).y
            visit(band,frame,baseline)
        }
    }
}

private struct WorkspaceDiffGutterLayout {
    static let font = NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium)

    let side:WorkspaceDiffSide, numberEdge:CGFloat
    var width:CGFloat {numberEdge+26}
    var markerCenter:CGFloat {width-13}

    init(side:WorkspaceDiffSide,maximumNumber:Int) {
        self.side = side
        let digits = max(3,String(maximumNumber).count)
        let sample = String(repeating:"0",count:digits) as NSString
        numberEdge = 10+ceil(sample.size(withAttributes:[.font:Self.font]).width)
    }
}

struct WorkspaceDiffDocument {
    let text:NSAttributedString
    let bands:[Int:WorkspaceDiffTextView.Band]
    let changes:[NSRange]
    fileprivate let gutterLayout:WorkspaceDiffGutterLayout

    init(_ review:WorkspaceDiffReview,side:WorkspaceDiffSide,path:String) {
        let font = NSFont.monospacedSystemFont(ofSize:12,weight:.regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 19; paragraph.maximumLineHeight = 19
        paragraph.defaultTabInterval = ("    " as NSString).size(withAttributes:[.font:font]).width
        let attributes:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph]
        let language = WorkspaceDiffSyntax.Language(path:path)
        let text = NSMutableAttributedString()
        var bands = [Int:WorkspaceDiffTextView.Band](), changes = [NSRange](), maximumNumber = 0

        func append(_ string:String,band:WorkspaceDiffTextView.Band,link:Int? = nil) -> NSMutableAttributedString {
            bands[text.length] = band
            let value = NSMutableAttributedString(string:string+"\n",attributes:attributes)
            if let link {value.addAttribute(.link,value:"bailong-diff-context:\(link)",range:NSRange(location:0,length:value.length-1))}
            switch band {
            case .context,.detail:
                value.addAttribute(.foregroundColor,value:NSColor.secondaryLabelColor,range:NSRange(location:0,length:value.length))
            default:break
            }
            return value
        }
        func appendCode(_ code:WorkspaceDiffReview.Code?) {
            guard let code else {text.append(append("",band:.spacer)); return}
            let value = append(code.text,band:.code(code.line))
            WorkspaceDiffSyntax.apply(language,to:value,text:code.text)
            if let range = code.emphasis,range.length > 0 {
                let tint = code.line.kind == .addition ? NSColor.systemGreen : NSColor.systemRed
                value.addAttribute(.backgroundColor,value:tint.withAlphaComponent(0.29),range:range)
            }
            maximumNumber = max(maximumNumber,side.lineNumber(for:code.line) ?? 0)
            text.append(value)
        }
        for row in review.rows {
            switch row {
            case .code(let code):appendCode(code)
            case .change(let pairs):
                let start = text.length
                switch side {
                case .inline:
                    pairs.compactMap(\.before).forEach {appendCode($0)}
                    pairs.compactMap(\.after).forEach {appendCode($0)}
                case .before:pairs.forEach {appendCode($0.before)}
                case .after:pairs.forEach {appendCode($0.after)}
                }
                changes.append(NSRange(location:start,length:0))
            case .fold(let id,let count,let expanded):
                let label = L10n.format(.workspace,expanded ? "workspaceDiff.fold.hide" : "workspaceDiff.fold.show",String(count))
                text.append(append(label,band:.context,link:id))
            case .gap(let count):
                text.append(append(L10n.format(.workspace,"workspaceDiff.gap",String(count)),band:.context))
            case .detail(let detail):text.append(append(detail,band:.detail))
            }
        }
        self.text = text; self.bands = bands; self.changes = changes
        gutterLayout = WorkspaceDiffGutterLayout(side:side,maximumNumber:maximumNumber)
    }
}

final class WorkspaceDiffPane:NSScrollView {
    let code:WorkspaceDiffTextView = {
        let storage = NSTextStorage(), manager = NSLayoutManager(), container = NSTextContainer()
        storage.addLayoutManager(manager); manager.addTextContainer(container)
        return WorkspaceDiffTextView(frame:.zero,textContainer:container)
    }()
    private lazy var gutter = WorkspaceDiffGutter(scrollView:self,orientation:.verticalRuler)

    override init(frame:NSRect) {
        super.init(frame:frame)
        hasVerticalScroller = true; hasHorizontalScroller = true; autohidesScrollers = true
        documentView = code
        // 将标尺重绘限制在行号栏内，避免盖住标题和正文。
        gutter.clipsToBounds = true
        verticalRulerView = gutter; hasVerticalRuler = true; rulersVisible = true
        gutter.clientView = code
        backgroundColor = .textBackgroundColor
        code.isEditable = false; code.isSelectable = true; code.isRichText = true; code.clipsToBounds = true
        code.drawsBackground = false
        code.isHorizontallyResizable = true; code.isVerticallyResizable = true
        code.autoresizingMask = [.width]; code.textContainerInset = NSSize(width:9,height:8)
        code.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        code.textContainer?.widthTracksTextView = false
        code.textContainer?.heightTracksTextView = false
        code.textContainer?.containerSize = code.maxSize
        contentView.postsBoundsChangedNotifications = true
    }
    required init?(coder:NSCoder) {fatalError()}

    func show(_ document:WorkspaceDiffDocument) {
        code.bands = document.bands
        gutter.numberLayout = document.gutterLayout
        code.textStorage?.setAttributedString(document.text)
        code.setSelectedRange(NSRange(location:0,length:0))
        code.layoutSubtreeIfNeeded()
        redrawRuler()
    }
    func clear() {
        code.bands = [:]
        code.textStorage?.setAttributedString(NSAttributedString())
    }
    func redrawRuler() {gutter.needsDisplay = true}
    func scroll(to position:NSPoint,resetHorizontal:Bool = false) {
        let point = resetHorizontal ? NSPoint(x:-gutter.ruleThickness,y:position.y) : position
        contentView.scroll(to:contentView.constrainBoundsRect(NSRect(origin:point,size:contentView.bounds.size)).origin)
        reflectScrolledClipView(contentView)
    }
}

private final class WorkspaceDiffGutter:NSRulerView {
    var numberLayout = WorkspaceDiffGutterLayout(side:.inline,maximumNumber:0) {
        didSet {ruleThickness = numberLayout.width}
    }
    override var isFlipped:Bool {true}
    override func drawHashMarksAndLabels(in rect:NSRect) {
        NSColor.windowBackgroundColor.setFill(); rect.fill()
        guard let text = clientView as? WorkspaceDiffTextView,let context = NSGraphicsContext.current?.cgContext else {return}
        let matrix = context.textMatrix, position = context.textPosition
        context.textMatrix = CGAffineTransform(scaleX:1,y:-1)
        defer {context.textMatrix = matrix; context.textPosition = position}
        text.visitBands(in:text.visibleRect) {band,line,baseline in
            if let fill = band.fill {
                let top = self.convert(NSPoint(x:0,y:line.minY),from:text).y
                fill.setFill()
                NSRect(x:0,y:top,width:self.ruleThickness,height:line.height).fill()
            }
            guard case .code(let row) = band else {return}
            let baselineY = self.convert(NSPoint(x:0,y:baseline),from:text).y
            let layout = self.numberLayout
            let tint = row.kind == .addition ? StatusTextColor.green : row.kind == .deletion ? StatusTextColor.red : .secondaryLabelColor
            if let number = layout.side.lineNumber(for:row) {
                self.draw(String(number),x:layout.numberEdge,baseline:baselineY,color:tint,in:context)
            }
            if row.kind == .addition || row.kind == .deletion {
                self.draw(row.kind == .addition ? "+" : "−",x:layout.markerCenter,baseline:baselineY,color:tint,in:context,centered:true)
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x:ruleThickness-1,y:rect.minY,width:1,height:rect.height).fill()
    }
    private func draw(_ value:String,x:CGFloat,baseline:CGFloat,color:NSColor,in context:CGContext,centered:Bool = false) {
        let attributes:[NSAttributedString.Key:Any] = [.font:WorkspaceDiffGutterLayout.font,.foregroundColor:color]
        let label = CTLineCreateWithAttributedString(NSAttributedString(string:value,attributes:attributes))
        let width = CTLineGetTypographicBounds(label,nil,nil,nil)
        context.textPosition = CGPoint(x:x-(centered ? width/2 : width),y:baseline)
        CTLineDraw(label,context)
    }
}

enum WorkspaceDiffSyntax {
    enum Language {
        case slash, hash, data, plain

        init(path:String) {
            let name = (path as NSString).lastPathComponent.lowercased()
            switch (name as NSString).pathExtension {
            case "swift","strings","m","mm","h","c","cc","cpp","hpp","js","jsx","mjs","cjs","ts","tsx","java","kt","go","rs","cs","css","scss":
                self = .slash
            case "py","rb","sh","bash","zsh","command","yml","yaml","toml":
                self = .hash
            case "json","jsonc":
                self = name.hasSuffix(".jsonc") ? .slash : .data
            default:
                self = ["makefile","dockerfile"].contains(name) ? .hash : .plain
            }
        }
    }
    private static let literals = #"("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\x60(?:\\.|[^\x60\\])*\x60)|(?<![\w.])(\d[\d_]*(?:\.\d[\d_]*)?)(?![\w.])|(@?\b[A-Za-z_$][\w$]*)"#
    private static let slash = try! NSRegularExpression(pattern:#"(//.*|/\*.*?(?:\*/|$))|"#+literals)
    private static let hash = try! NSRegularExpression(pattern:#"(#.*)|"#+literals)
    private static let data = try! NSRegularExpression(pattern:#"(\b\B)|"#+literals)
    private static let keywords = Set("""
        actor any as async await break case catch class const continue def defer do else enum export extension
        fallthrough false final for from func function guard if import in init interface is lambda let match
        mut nil none null override package private protected protocol public raise return self some static struct
        super switch throw throws trait true try type typealias undefined val var void where while with yield
        """.split(separator:" "))

    static func apply(_ language:Language,to value:NSMutableAttributedString,text:String) {
        let expression:NSRegularExpression
        switch language {
        case .slash:expression = slash
        case .hash:expression = hash
        case .data:expression = data
        case .plain:return
        }
        let source = text as NSString
        guard source.length > 0,source.length <= 8192 else {return}
        expression.enumerateMatches(in:text,range:NSRange(location:0,length:source.length)) {match,_,_ in
            guard let match else {return}
            let color:NSColor
            if match.range(at:1).location != NSNotFound {color = .secondaryLabelColor}
            else if match.range(at:2).location != NSNotFound {color = StatusTextColor.green}
            else if match.range(at:3).location != NSNotFound {color = StatusTextColor.orange}
            else {
                let word = source.substring(with:match.range)
                if keywords.contains(Substring(word.lowercased())) || word.hasPrefix("@") {color = StatusTextColor.purple}
                else if word.first?.isUppercase == true {color = StatusTextColor.teal}
                else {
                    let end = NSMaxRange(match.range)
                    guard end < source.length,source.character(at:end) == 40 else {return}
                    color = StatusTextColor.blue
                }
            }
            value.addAttribute(.foregroundColor,value:color,range:match.range)
        }
    }
}
