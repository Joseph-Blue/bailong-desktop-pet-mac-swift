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
        [turn.bodyReference.id,turn.status,String(turn.finished),String(turn.date.timeIntervalSince1970),turn.completedAt.map {String($0.timeIntervalSince1970)} ?? "",turn.tokenUsage?.signature ?? "",turn.tokenUsageError ?? ""]
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
            append(L10n.text(.conversation,"transcriptRenderer.appendMarkdown.text")+PetPreferences.shared.petName+L10n.text(.conversation,"transcriptRenderer.appendMarkdown.text.2"),font:.systemFont(ofSize:18,weight:.semibold),color:AppAccent.foregroundColor)
            append(conversation.external ? L10n.text(.conversation,"transcriptRenderer.appendMarkdown.text.3") : PetPreferences.shared.statusLine("conversationEmptyTemplate"),color:.secondaryLabelColor)
            return result
        }
        let style = style(conversation)
        let keys = Set(turns.map(\.key))
        transcriptCache = transcriptCache.filter {keys.contains($0.key)}
        for turn in turns {
            if result.length > 0 {result.append(NSAttributedString(string:"\n",attributes:[.font:NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))]))}
            let signature = style + turnSignature(turn)
            if let cached = transcriptCache[turn.key],cached.0 == signature {result.append(cached.1); continue}
            let body = turn.bodyReference.value()
            let accumulated = result
            result = NSMutableAttributedString()
            let bodyFont = NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))
            let headingFont = NSFont.systemFont(ofSize:bodyFont.pointSize+2,weight:.semibold)
            if !body.input.isEmpty {
                result.append(TranscriptIcon.render(NSImage(systemSymbolName:"person.crop.circle",accessibilityDescription:L10n.text(.conversation,"transcriptRenderer.appendMarkdown.accessibilityDescription")),font:headingFont,description:L10n.text(.conversation,"transcriptRenderer.appendMarkdown.accessibilityDescription")))
                append(PetPreferences.shared.address+" · "+turn.date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits)),font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")+2,weight:.semibold),color:AppAccent.foregroundColor,after:6)
                result.append(MarkdownText.renderUserInput(body.input,font:.systemFont(ofSize:PetPreferences.shared.number("messageFontSize"))))
                // 消息之间保留空行；分隔符使用正文样式，不继承末尾链接或行内代码属性。
                let separator = NSMutableParagraphStyle(); separator.lineSpacing = 2
                let lineBreaks = result.string.hasSuffix("\n\n") ? "" : result.string.hasSuffix("\n") ? "\n" : "\n\n"
                result.append(NSAttributedString(string:lineBreaks,attributes:[
                    .font:NSFont.systemFont(ofSize:PetPreferences.shared.number("messageFontSize")),
                    .foregroundColor:NSColor.labelColor,.paragraphStyle:separator]))
            }
            result.append(TranscriptIcon.render(AppIcons.petAvatarTemplate,font:headingFont,description:PetPreferences.shared.petName))
            append(turn.status == "completed" ? PetPreferences.shared.petName+" · 「"+PetPreferences.shared.taskResultLine("completed")+"」" : PetPreferences.shared.petName+" · "+turnStatus(turn.status),font:headingFont,color:AppAccent.foregroundColor,after:6)
            // 只隐藏旧版外部观察器合成的步骤报错，不删历史字段或原始对话内容。
            let steps = conversation.external && body.steps.hasPrefix("这一步执行遇到问题，任务尚未报告完成。") ? "" : body.steps
            for (heading,text,isSummary) in [(L10n.text(.conversation,"transcriptRenderer.appendMarkdown.text.4"),body.summary,true),(L10n.text(.conversation,"transcriptRenderer.appendMarkdown.text.5"),steps,false)] where !text.isEmpty {
                append(heading,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1),weight:.medium),color:.secondaryLabelColor,after:4)
                if isSummary {appendMarkdown(text,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1)),color:.secondaryLabelColor)}
                else {append(text,font:.systemFont(ofSize:max(11,PetPreferences.shared.number("messageFontSize")-1)),color:.secondaryLabelColor)}
            }
            if let notice = body.sensitiveQuestionNotice {append(notice,color:.secondaryLabelColor)}
            if let notice = body.sensitiveInputNotice {append(notice,color:.secondaryLabelColor)}
            if !body.messages.isEmpty {appendMarkdown(body.messages)}
            if !body.final.isEmpty && !body.messages.contains(body.final) {appendMarkdown(body.final)}
            if turn.finished {
                result.append(FileEditRendering.render(body.fileEdits ?? [],font:bodyFont,id:turn.key))
            }
            if !body.error.isEmpty {let failure = AppFailure.codex(body.error); append(failure.title+"\n"+failure.message,color:.secondaryLabelColor)}
            var reply = [body.messages]
            if !body.final.isEmpty && !body.messages.contains(body.final) {reply.append(body.final)}
            if !body.error.isEmpty {
                let failure = AppFailure.codex(body.error)
                reply.append(failure.title+"\n"+failure.message)
            }
            result.append(TranscriptActions(TurnCompletion(turn,completedAt:turn.completedAt),font:bodyFont,text:reply.filter {!$0.isEmpty}.joined(separator:"\n\n"),threadID:conversation.threadID).placeholder())
            transcriptCache[turn.key] = (signature,result)
            accumulated.append(result); result = accumulated
        }
        return result
    }
    private func turnStatus(_ value: String) -> String {
        ["pending":L10n.text(.conversation,"transcriptRenderer.turnStatus.text"),"running":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.2"),"inProgress":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.2"),"completed":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.3"),"failed":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.4"),"interrupted":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.5"),"cancelled":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.6"),"canceled":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.6"),"waitingForApproval":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.7"),"waitingForInput":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.8"),"unknown":L10n.text(.conversation,"transcriptRenderer.turnStatus.text.9")][value] ?? L10n.text(.conversation,"transcriptRenderer.turnStatus.text.9")
    }
}
