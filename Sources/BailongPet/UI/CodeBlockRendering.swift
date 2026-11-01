import AppKit

extension NSAttributedString.Key {
    static let codeBlockHeader = NSAttributedString.Key("BailongCodeBlockHeader")
}

final class CodeBlockContent:NSObject {
    let code:String, language:String
    let font:NSFont
    init(code:String,language:String,font:NSFont) {self.code = code; self.language = language; self.font = font}
    var label:String {
        ["swift":"Swift","python":"Python","py":"Python","js":"JavaScript","javascript":"JavaScript","ts":"TypeScript","typescript":"TypeScript","json":"JSON","html":"HTML","css":"CSS","sql":"SQL" ][language.lowercased()] ?? (language.isEmpty ? "代码" : language)
    }
    override func isEqual(_ object:Any?) -> Bool {
        guard let other = object as? CodeBlockContent else {return false}
        return code == other.code && language == other.language && font == other.font
    }
    override var hash:Int {code.hashValue ^ language.hashValue ^ font.hash}
    func copyCode() {NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code,forType:.string)}
}

// 单个原生文本表格单元承载语言栏与正文，绘制统一圆角边界。
private final class RoundedCodeBlock:NSTextTableBlock {
    override func drawBackground(withFrame frameRect:NSRect,in controlView:NSView?,characterRange:NSRange,layoutManager:NSLayoutManager) {
        let rect = frameRect.insetBy(dx:0.5,dy:0.5)
        let path = NSBezierPath(roundedRect:rect,xRadius:8,yRadius:8)
        NSColor.controlBackgroundColor.setFill(); path.fill()
        NSColor.separatorColor.setStroke(); path.lineWidth = 0.5; path.stroke()
    }
}

enum CodeBlockRendering {
    static func highlighted(_ code:String,language:String,font:NSFont) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string:code,attributes:[.font:font,.foregroundColor:NSColor.labelColor])
        let language = language.lowercased()
        let supported:Set<String> = ["swift","python","py","javascript","js","typescript","ts","jsx","tsx","json","bash","sh","zsh","shell","c","cpp","c++","csharp","cs","java","go","rust","rs","sql","yaml","yml"]
        guard supported.contains(language) else {return result}
        // 单次词法扫描，注释与字符串内部不再次染色；不改变原文、缩进和搜索索引。
        let pattern = #"(?s:/\*.*?(?:\*/|\z))|(?m://[^\n]*|#[^\n]*)|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\b[0-9]+(?:\.[0-9]+)?\b|\b[A-Za-z_][A-Za-z_0-9]*\b"#
        let regex = try! NSRegularExpression(pattern:pattern)
        let keywords:Set<String> = Set("let var func function class struct enum protocol extension import from return if else guard switch case default break continue for while in do try catch throw throws async await public private static final override init nil null true false def lambda pass with as elif except finally raise yield const export new interface type package fn impl pub use mut match self super select where insert into update delete join and or not is end then fi done local".split(separator:" ").map(String.init))
        let ns = code as NSString
        let hashComments = ["python","py","bash","sh","zsh","shell","yaml","yml"].contains(language)
        for match in regex.matches(in:code,range:NSRange(location:0,length:ns.length)) {
            let token = ns.substring(with:match.range), color:NSColor?
            if token.hasPrefix("//") || token.hasPrefix("/*") || (hashComments && token.hasPrefix("#")) {color = .secondaryLabelColor}
            else if token.hasPrefix("\"") || token.hasPrefix("'") || token.hasPrefix("`") {color = .systemGreen}
            else if keywords.contains(token.lowercased()) {color = .systemPink}
            else if token.first?.isNumber == true {color = .systemOrange}
            else if NSMaxRange(match.range) < ns.length,ns.substring(from:NSMaxRange(match.range)).drop(while:{$0 == " "}).first == "(" {color = .systemPurple}
            else {color = nil}
            if let color {result.addAttribute(.foregroundColor,value:color,range:match.range)}
        }
        return result
    }
    static func render(_ code:String,language:String,font:NSFont) -> NSAttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize:max(10,font.pointSize-1),weight:.regular)
        let data = CodeBlockContent(code:code,language:language,font:mono)
        let table = NSTextTable(); table.numberOfColumns = 1; table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.setContentWidth(100,type:.percentageValueType); table.collapsesBorders = true
        let cell = RoundedCodeBlock(table:table,startingRow:0,rowSpan:1,startingColumn:0,columnSpan:1)
        cell.setContentWidth(100,type:.percentageValueType); cell.setWidth(10,type:.absoluteValueType,for:.padding)
        func paragraph(_ row:Int) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle(); style.textBlocks = [cell]; style.paragraphSpacing = 0; style.lineSpacing = 2
            style.defaultTabInterval = ("    " as NSString).size(withAttributes:[.font:mono]).width
            style.lineBreakMode = .byCharWrapping
            if row == 0 {style.tailIndent = -38; style.minimumLineHeight = max(24,font.pointSize+8); style.paragraphSpacing = 8}
            return style
        }
        let result = NSMutableAttributedString(string:data.label+"\n",attributes:[.font:NSFont.systemFont(ofSize:font.pointSize,weight:.medium),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:paragraph(0),.codeBlockHeader:data])
        let body = highlighted(code,language:language,font:mono)
        if !code.hasSuffix("\n") {body.append(NSAttributedString(string:"\n",attributes:[.font:mono]))}
        body.addAttribute(.paragraphStyle,value:paragraph(1),range:NSRange(location:0,length:body.length))
        result.append(body); return result
    }
}

final class CodeBlockToolbar:NSView {
    var content:CodeBlockContent
    private let copyButton:NSButton
    init(_ content:CodeBlockContent) {
        self.content = content
        copyButton = NSButton(image:NSImage(systemSymbolName:"doc.on.doc",accessibilityDescription:"复制代码")!,target:nil,action:nil)
        super.init(frame:NSRect(x:0,y:0,width:30,height:26))
        copyButton.isBordered = false; copyButton.bezelStyle = .inline; copyButton.target = self
        copyButton.frame = NSRect(x:0,y:0,width:28,height:26); addSubview(copyButton)
        copyButton.action = #selector(copyCode); copyButton.hoverHelp = "复制完整代码"
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func copyCode() {content.copyCode()}
}
