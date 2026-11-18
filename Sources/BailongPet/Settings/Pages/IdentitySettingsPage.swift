import AppKit

enum IdentitySettingsPage {
    static let editWorkingLineTitle = "编辑工作中台词"
    static func workingLineEditTarget(_ prefs:PetPreferences) -> (group:String,key:String) {
        prefs.bool("randomWorkingLines") ? ("工作中台词",ConversationLines.working[0].key) : ("任务状态台词","taskProgressTemplate")
    }
    static func render(form:SettingsForm,catalog:Catalog?,window:NSWindow,onLinePreview:@escaping (Clip,String) -> Void,
                       play:@escaping (SettingsListItem) -> Void,reload:@escaping () -> Void) -> SettingsRowViewport? {
        let preferences = form.preferences
        func templatePreview(_ title:String,key:String,clip:Clip?) -> ActionButton {
            let button = form.animationPreviewButton(title,compact:true) { [weak window] in
                guard let clip,window?.makeFirstResponder(nil) == true else {return}
                onLinePreview(clip,preferences.statusLine(key))
            }
            button.isEnabled = clip != nil
            return button
        }
        form.fill(form.note("{用户名} 是你的名字，{桌宠名} 是桌宠的名字；{特定称呼} 使用下面填写的内容，留空沿用你的名字。右键点击台词或特定称呼输入框，可插入这些变量。"),in:form.content)
        let names = [form.text("你的名字","ownerName",placeholder:"默认为“主人”"),form.text("桌宠的名字","petName",placeholder:"白龙娘"),form.text("特定称呼","customAddress",placeholder:"留空沿用你的名字，可以插入变量")]
        form.group("我们怎么称呼彼此",names,symbol:"person.2")
        let greetingPreview = templatePreview("问候语",key:"greetingTemplate",clip:catalog?.variants.first(where:{$0.id == "01"}))
        form.group("见面时说",[form.text("问候语","greetingTemplate",limit:120,action:greetingPreview)],symbol:"hand.wave")
        let grouped = Dictionary(grouping:items(catalog:catalog),by:\.group)
        let previewHeight = greetingPreview.fittingSize.height
        var lineRows = [IdentityLineRow]()
        func rows(_ group:String) -> [NSView] {
            (grouped[group] ?? []).map { item in
                let row = IdentityLineRow(item:item,preferences:preferences,previewHeight:previewHeight,play:play)
                lineRows.append(row)
                return form.searchable(row,title:item.id)
            }
        }
        func restore(_ group:SettingsLineResetGroup) -> NSButton {
            let button = ActionButton("恢复默认") { [weak window] in
                guard window?.makeFirstResponder(nil) == true else {return}
                group.restore(in:preferences); reload()
            }
            button.controlSize = .small; button.font = .systemFont(ofSize:11)
            button.setAccessibilityLabel("恢复"+group.rawValue+"为默认值")
            return button
        }
        form.group("工作中台词",[
            form.toggle("随机工作中台词抽取","randomWorkingLines",detail:"有执行中任务时，每次打开任务概览随机抽取一句。关闭后使用“执行任务中”台词。")
        ] + rows("工作中台词"),symbol:"briefcase",action:restore(.working))
        form.group("任务状态台词",rows("任务状态台词"),symbol:"checklist")
        form.group("聊天窗口台词",rows("聊天窗口台词"),symbol:"bubble.left.and.bubble.right")
        form.group("额度查询台词",rows("额度查询台词"),symbol:AppIcons.quotaSymbol)
        if grouped["互动台词"] != nil {
            form.group("互动台词",rows("互动台词"),symbol:"figure.play",action:restore(.interaction))
        }
        guard let scroll = form.content.enclosingScrollView else {return nil}
        return SettingsRowViewport(rows:lineRows,scroll:scroll)
    }

    static func items(catalog:Catalog?) -> [SettingsListItem] {
        func templates(_ group:String,_ entries:[ConversationLines.Entry]) -> [SettingsListItem] {
            entries.map {.init(group:group,title:$0.title,kind:.template($0.key,preview:nil),keywords:"台词 模板 "+$0.text)}
        }
        var result = templates("工作中台词",ConversationLines.working) + templates("任务状态台词",ConversationLines.task)
        for (title,key,keywords) in [
            ("执行任务中","taskProgressTemplate","我还在留意进展"),("有新进展","taskUpdateTemplate","进度 任务计划 阶段性进展 Codex 项目任务 我忙到这一步啦"),
            ("等待回答","taskAnswerTemplate","审批"),("等待批准","taskApprovalTemplate","审批"),
            ("任务成功","taskSuccessTemplate",""),("任务失败","taskFailureTemplate",""),("任务中断或取消","taskInterruptedTemplate","")
        ] {
            result.append(.init(group:"任务状态台词",title:title,kind:.template(key,preview:nil),keywords:"台词 模板 "+keywords))
        }
        result += templates("聊天窗口台词",ConversationLines.interface)
        result.append(.init(group:"额度查询台词",title:"正在查询",kind:.template("quotaLoadingTemplate",preview:catalog?.quotaAnimation),keywords:"额度 ChatGPT 订阅 台词 动作 播放 预览"))
        if let catalog {
            result += (catalog.variants+catalog.work).filter {$0.line != nil}.map {
                .init(group:"互动台词",title:$0.title,kind:.interaction($0),keywords:"台词 模板 动作 播放 预览")
            }
        }
        return result
    }
}

private final class IdentityLineRow:NSView,SettingsViewportRow {
    private let item:SettingsListItem
    private let preferences:PetPreferences
    private let play:(SettingsListItem) -> Void
    private let caption:NSTextField
    private var editor:(form:SettingsForm,view:NSView)?
    var isLoaded:Bool {editor != nil}

    init(item:SettingsListItem,preferences:PetPreferences,previewHeight:CGFloat,play:@escaping (SettingsListItem) -> Void) {
        self.item = item; self.preferences = preferences; self.play = play
        caption = label(item.title)
        super.init(frame:.zero)
        setAccessibilityRole(.group); setAccessibilityLabel(item.title)
        caption.translatesAutoresizingMaskIntoConstraints = false; addSubview(caption)
        let captionHeight = caption.fittingSize.height
        let headerHeight = item.preview == nil ? captionHeight : max(captionHeight,previewHeight)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant:headerHeight+SettingsForm.multilineEntryHeight+SettingsForm.multilineEntrySpacing),
            caption.leadingAnchor.constraint(equalTo:leadingAnchor),caption.trailingAnchor.constraint(equalTo:trailingAnchor),
            caption.topAnchor.constraint(equalTo:topAnchor,constant:(headerHeight-captionHeight)/2)
        ])
    }
    required init?(coder:NSCoder) {fatalError()}

    func loadControls() {
        guard !isLoaded,let window else {return}
        let form = SettingsForm(content:NSStackView(),preferences:preferences,window:window)
        form.reset(section:.identity)
        let item = item, play = play
        guard let view = item.lineEditor(in:form,onPreview:{ [weak window] in
            guard window?.makeFirstResponder(nil) == true else {return}
            play(item)
        }) else {return}
        editor = (form,view)
        caption.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo:leadingAnchor),view.trailingAnchor.constraint(equalTo:trailingAnchor),
            view.topAnchor.constraint(equalTo:topAnchor),view.bottomAnchor.constraint(equalTo:bottomAnchor)
        ])
    }
    func releaseControls() {
        editor?.view.removeFromSuperview(); editor = nil; caption.isHidden = false
    }

    override var acceptsFirstResponder:Bool {!isLoaded}
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else {return false}
        scrollToVisible(bounds); loadControls()
        DispatchQueue.main.async { [weak self] in
            guard let self,let window = self.window,window.firstResponder === self,
                  let field = self.editor?.form.currentTemplateField else {return}
            window.makeFirstResponder(field)
        }
        return true
    }
    override func accessibilityChildren() -> [Any]? {
        loadControls()
        return super.accessibilityChildren()
    }
}
