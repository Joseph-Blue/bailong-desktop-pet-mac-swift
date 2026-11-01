import AppKit

enum ApprovalText {
    static func render(_ form:ApprovalPresentation,font:NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 2; paragraph.paragraphSpacing = 8
        let base:[NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph]
        for section in form.request.detailSections {
            var heading = base; heading[.font] = NSFont.systemFont(ofSize:font.pointSize,weight:.semibold)
            result.append(NSAttributedString(string:section.title+"\n",attributes:heading))
            if let language = section.codeLanguage {
                // 直接传入原命令，不将反引号或 Markdown 字符解释为操作说明。
                result.append(CodeBlockRendering.render(section.text,language:language,font:font))
            } else if section.key == "reason" {
                result.append(MarkdownText.render(section.text,font:font,lineSpacing:2,paragraphSpacing:8))
            } else {result.append(NSAttributedString(string:section.text,attributes:base))}
            result.append(NSAttributedString(string:"\n",attributes:base))
        }
        if result.length == 0 {result.append(NSAttributedString(string:form.request.attention.body+"\n",attributes:base))}
        if !form.statusText.isEmpty {result.append(NSAttributedString(string:form.statusText,attributes:base))}
        return result
    }
}
