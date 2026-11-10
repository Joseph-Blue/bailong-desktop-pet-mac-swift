import AppKit

// 只生成历史富文本并拥有其缓存，不管理窗口、输入或阅读位置。
final class TranscriptRenderer {
    private var transcriptCache = [String:([String],NSAttributedString)]()
    func invalidate() {transcriptCache.removeAll()}
    func style(_ conversation:Conversation) -> [String] {
        let preferences = PetPreferences.shared
        return [preferences.statusLine("conversationEmptyTemplate"),preferences.petName,preferences.address,preferences.taskResultLine("completed"),String(preferences.number("messageFontSize")),String(conversation.external),conversation.threadID ?? ""]
    }
    func turnSignature(_ turn:Turn) -> [String] {
        [turn.bodyReference.id,turn.status,String(turn.date.timeIntervalSince1970),turn.completedAt.map {String($0.timeIntervalSince1970)} ?? ""]
    }
    func content(_ conversation: Conversation, turns:[Turn]? = nil) -> NSAttributedString {
        let turns = turns ?? conversation.turns
        var result = NSMutableAttributedString()
        func append(_ text: String, font: NSFont = .systemFont(ofSize:PetPreferences.shared.number("messageFontSize")), color: NSColor = .labelColor, after: CGFloat = 12) {
            guard !text.isEmpty else {return}
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.paragraphSpacing = after
            result.append(NSAttributedString(string:text+"\n",attributes:[.font:font,.foregroundColor:color,.paragraphStyle:paragraph]))
        }
        func appendMarkdown(_ text: String, font: NSFont = .systemFont(ofSize:PetPreferences.shared.number("messageFontSize")), color: NSColor = .labelColor) {
            guard !text.isEmpty else{return}
            result.append(MarkdownText.render(text,font:font,color:color))
            result.append(NSAttributedString(string:"\n",attributes:[.font:font]))
        }
        if turns.isEmpty {
            invalidate()
            append("与"+PetPreferences.shared.petName+"聊聊",font:.systemFont(ofSize:18,weight:.semibold),color:AppAccent.color)
            append(conversation.external ? "在下方输入想做的事。" : PetPreferences.shared.statusLine("conversationEmptyTemplate"),color:.secondaryLabelColor)
            return result
        }
        let style = style(conversation)
        let keys = Set(turns.map(\.key))
        transcriptCache = transcriptCache.filter {keys.contains($0.key)}
        for turn in turns {
            let signature = style + turnSignature(turn)
            if let cached = transcriptCache[turn.key],cached.0 == signature {result.append(cached.1); continue}
            let body = turn.bodyReference.value()
            let accumulated = result
            result = NSMutableAttributedString()
            let bodyFont = NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))
            let headingFont = NSFont.systemFont(ofSize:bodyFont.pointSize+2,weight:.semibold)
            if !body.input.isEmpty {
                result.append(TranscriptIcon.render(NSImage(systemSymbolName:"person.crop.circle",accessibilityDescription:"用户"),font:headingFont,description:"用户"))
                append(PetPreferences.shared.address+" · "+turn.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits)),font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")+2,weight:.semibold),color:AppAccent.color,after:6)
                result.append(MarkdownText.renderUserInput(body.input,font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))))
                // 消息之间保留空行；分隔符使用正文样式，不继承末尾链接或行内代码属性。
                let separator = NSMutableParagraphStyle(); separator.lineSpacing = 2
                let lineBreaks = result.string.hasSuffix("\n\n") ? "" : result.string.hasSuffix("\n") ? "\n" : "\n\n"
                result.append(NSAttributedString(string:lineBreaks,attributes:[
                    .font:NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")),
                    .foregroundColor:NSColor.labelColor,.paragraphStyle:separator]))
            }
            result.append(TranscriptIcon.render(AppIcons.petAvatarTemplate,font:headingFont,description:PetPreferences.shared.petName))
            append(turn.status == "completed" ? PetPreferences.shared.petName+" · 「"+PetPreferences.shared.taskResultLine("completed")+"」" : PetPreferences.shared.petName+" · "+turnStatus(turn.status),font:headingFont,color:AppAccent.color,after:6)
            // 只隐藏旧版外部观察器合成的步骤报错，不删历史字段或原始对话内容。
            let steps = conversation.external && body.steps.hasPrefix("这一步执行遇到问题，任务尚未报告完成。") ? "" : body.steps
            for (heading,text) in [("公开思考摘要",body.summary),("执行记录",steps)] where !text.isEmpty {
                append(heading,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1),weight:.medium),color:.secondaryLabelColor,after:4)
                if heading == "公开思考摘要" {appendMarkdown(text,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1)),color:.secondaryLabelColor)}
                else {append(text,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1)),color:.secondaryLabelColor)}
            }
            if let notice = body.sensitiveQuestionNotice {append(notice,color:.secondaryLabelColor)}
            if let notice = body.sensitiveInputNotice {append(notice,color:.secondaryLabelColor)}
            if !body.messages.isEmpty {appendMarkdown(body.messages)}
            if !body.final.isEmpty && !body.messages.contains(body.final) {appendMarkdown(body.final)}
            result.append(FileEditRendering.render(body.fileEdits ?? [],font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")),id:turn.key))
            if !body.error.isEmpty {let failure = AppFailure.codex(body.error); append(failure.title+"\n"+failure.message,color:.secondaryLabelColor)}
            if let ended = endLabel(turn.status) {
                let time = turn.completedAt.map { $0.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits)) } ?? "时间未提供"
                append(ended+" · "+time,font:.systemFont(ofSize:max(11,bodyFont.pointSize-1)),color:AppAccent.color,after:4)
            }
            var reply = [body.messages]
            if !body.final.isEmpty && !body.messages.contains(body.final) {reply.append(body.final)}
            if !body.error.isEmpty {
                let failure = AppFailure.codex(body.error)
                reply.append(failure.title+"\n"+failure.message)
            }
            result.append(TranscriptActions(id:turn.key,text:reply.filter {!$0.isEmpty}.joined(separator:"\n\n"),threadID:conversation.threadID,font:bodyFont).placeholder())
            transcriptCache[turn.key] = (signature,result)
            accumulated.append(result); result = accumulated
        }
        return result
    }
    private func endLabel(_ status:String) -> String? {
        ["completed":"完成","failed":"失败","interrupted":"中断","cancelled":"停止","canceled":"停止"][status]
    }
    private func turnStatus(_ value: String) -> String {
        ["pending":"准备中","running":"处理中","inProgress":"处理中","completed":"已完成","failed":"未完成","interrupted":"已中断","cancelled":"已停止","canceled":"已停止","waitingForApproval":"等待批准","waitingForInput":"等待补充","unknown":"状态待确认"][value] ?? "状态待确认"
    }
}
