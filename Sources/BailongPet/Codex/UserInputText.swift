import Foundation

// 只投影桌面端附件包装；用户正文不按标题放大，也不保存图片载荷。
enum UserInputText {
    static let header = "# Files mentioned by the user:"
    static let requestMarker = "\n## My request:\n"
    static let limit = 8192

    static func display(_ source:String,request:String? = nil,images:Int = 0,files:Int = 0,limitBody:Bool = false) -> String {
        var text = source
        var attachments = [String]()
        var linkedImages = 0
        let normalized = source.replacingOccurrences(of:"\r\n",with:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
        if normalized.hasPrefix(header) {
            let body = request ?? normalized.range(of:requestMarker).map({String(normalized[$0.upperBound...])})
            let metadata = normalized.components(separatedBy:requestMarker)[0]
            let entries = metadata.components(separatedBy:"\n## ").dropFirst()
            for entry in entries {
                let line = entry.components(separatedBy:"\n")[0]
                guard let separator = line.range(of:": /",options:.backwards) else {continue}
                let path = String(line[line.index(after:separator.lowerBound)...]).trimmingCharacters(in:.whitespaces)
                let image = entry.components(separatedBy:"\n").contains("Image attachment: true")
                if image {linkedImages += 1}
                let name = image ? L10n.text(.tasks,"userInputText.display.text") : URL(fileURLWithPath:path).lastPathComponent
                let label = name.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"[",with:"\\[").replacingOccurrences(of:"]",with:"\\]")
                attachments.append("[\(label)](<\(URL(fileURLWithPath:path).absoluteString)>)")
            }
            if let body {
                text = body.trimmingCharacters(in:.whitespacesAndNewlines)
                // 旧投影曾在完整包装末尾追加图片占位；已有同份图片链接时去掉该占位。
                if linkedImages > 0 {
                    let placeholder = linkedImages == 1 ? L10n.text(.tasks,"userInputText.placeholder") : L10n.format(.tasks,"userInputText.placeholder.2",String(describing:linkedImages))
                    if text == placeholder {text = ""}
                    else if text.hasSuffix("\n\n"+placeholder) {text.removeLast(2+placeholder.count)}
                }
                if attachments.isEmpty {attachments = [L10n.text(.tasks,"userInputText.display.text.2")]}
            } else if !attachments.isEmpty {
                // 包装尚未完整到达时只呈现已知附件，不把路径清单当用户提问。
                text = ""
            }
        } else {
            if images > 0 {attachments.append(images == 1 ? L10n.text(.tasks,"userInputText.placeholder") : L10n.format(.tasks,"userInputText.placeholder.2",String(describing:images)))}
            if files > 0 {attachments.append(files == 1 ? L10n.text(.tasks,"userInputText.display.text.2") : L10n.format(.tasks,"userInputText.display.text.3",String(describing:files)))}
        }
        let body = limitBody && text.count > limit ? String(text.prefix(limit))+"…" : text
        return [body.trimmingCharacters(in:.whitespacesAndNewlines),attachments.joined(separator:"  ·  ")]
            .filter {!$0.isEmpty}.joined(separator:"\n")
    }
}
