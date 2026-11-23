import AppKit

enum IdentitySettingsPage {
    static let editWorkingLineTitle = L10n.text(.settings,"identity.editWorkingLineTitle")
    static func workingLineEditTarget(_ prefs:PetPreferences) -> (group:String,key:String) {
        prefs.bool("randomWorkingLines") ? (L10n.text(.settings,"identity.workingLineEditTarget.text"),ConversationLines.working[0].key) : (L10n.text(.settings,"identity.workingLineEditTarget.text.2"),"taskProgressTemplate")
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
        form.fill(form.note(L10n.text(.settings,"identity.templatePreview.paragraph")),in:form.content)
        let names = [form.text(L10n.text(.settings,"identity.names"),"ownerName",placeholder:L10n.text(.settings,"identity.names.2")),form.text(L10n.text(.settings,"identity.names.3"),"petName",placeholder:L10n.text(.settings,"identity.names.4")),form.text(L10n.text(.settings,"identity.names.5"),"customAddress",placeholder:L10n.text(.settings,"identity.names.6"))]
        form.group(L10n.text(.settings,"identity.templatePreview.text"),names,symbol:"person.2")
        let greetingPreview = templatePreview(L10n.text(.settings,"identity.greetingPreview"),key:"greetingTemplate",clip:catalog?.variants.first(where:{$0.id == "01"}))
        form.group(L10n.text(.settings,"identity.templatePreview.text.2"),[form.text(L10n.text(.settings,"identity.greetingPreview"),"greetingTemplate",limit:120,action:greetingPreview)],symbol:"hand.wave")
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
            let button = ActionButton(L10n.text(.settings,"identity.restore.button")) { [weak window] in
                guard window?.makeFirstResponder(nil) == true else {return}
                group.restore(in:preferences); reload()
            }
            button.controlSize = .small; button.font = .systemFont(ofSize:11)
            button.setAccessibilityLabel(L10n.text(.settings,"identity.restore.text")+group.title+L10n.text(.settings,"identity.restore.text.2"))
            return button
        }
        form.group(L10n.text(.settings,"identity.workingLineEditTarget.text"),[
            form.toggle(L10n.text(.settings,"identity.randomWorkingLines.title"),"randomWorkingLines",detail:L10n.text(.settings,"identity.randomWorkingLines.detail"))
        ] + rows(L10n.text(.settings,"identity.workingLineEditTarget.text")),symbol:"briefcase",action:restore(.working))
        form.group(L10n.text(.settings,"identity.workingLineEditTarget.text.2"),rows(L10n.text(.settings,"identity.workingLineEditTarget.text.2")),symbol:"checklist")
        form.group(L10n.text(.settings,"identity.restore.text.3"),rows(L10n.text(.settings,"identity.restore.text.3")),symbol:"bubble.left.and.bubble.right")
        form.group(L10n.text(.settings,"identity.restore.text.4"),rows(L10n.text(.settings,"identity.restore.text.4")),symbol:AppIcons.quotaSymbol)
        if grouped[L10n.text(.settings,"identity.restore.text.5")] != nil {
            form.group(L10n.text(.settings,"identity.restore.text.5"),rows(L10n.text(.settings,"identity.restore.text.5")),symbol:"figure.play",action:restore(.interaction))
        }
        guard let scroll = form.content.enclosingScrollView else {return nil}
        return SettingsRowViewport(rows:lineRows,scroll:scroll)
    }

    static func items(catalog:Catalog?) -> [SettingsListItem] {
        func templates(_ group:String,_ entries:[ConversationLines.Entry]) -> [SettingsListItem] {
            entries.map {.init(group:group,title:$0.title,kind:.template($0.key,preview:nil),keywords:L10n.text(.settings,"identity.templates.keywords")+$0.text)}
        }
        var result = templates(L10n.text(.settings,"identity.workingLineEditTarget.text"),ConversationLines.working) + templates(L10n.text(.settings,"identity.workingLineEditTarget.text.2"),ConversationLines.task)
        for (title,key,keywords) in [
            (L10n.text(.settings,"identity.templates.text"),"taskProgressTemplate",L10n.text(.settings,"identity.templates.text.2")),(L10n.text(.settings,"identity.templates.text.3"),"taskUpdateTemplate",L10n.text(.settings,"identity.templates.text.4")),
            (L10n.text(.settings,"identity.templates.text.5"),"taskAnswerTemplate",L10n.text(.settings,"identity.templates.text.6")),(L10n.text(.settings,"identity.templates.text.7"),"taskApprovalTemplate",L10n.text(.settings,"identity.templates.text.6")),
            (L10n.text(.settings,"identity.templates.text.8"),"taskSuccessTemplate",""),(L10n.text(.settings,"identity.templates.text.9"),"taskFailureTemplate",""),(L10n.text(.settings,"identity.templates.text.10"),"taskInterruptedTemplate","")
        ] {
            result.append(.init(group:L10n.text(.settings,"identity.workingLineEditTarget.text.2"),title:title,kind:.template(key,preview:nil),keywords:L10n.text(.settings,"identity.templates.keywords")+keywords))
        }
        result += templates(L10n.text(.settings,"identity.restore.text.3"),ConversationLines.interface)
        result.append(.init(group:L10n.text(.settings,"identity.restore.text.4"),title:L10n.text(.settings,"identity.templates.title"),kind:.template("quotaLoadingTemplate",preview:catalog?.quotaAnimation),keywords:L10n.text(.settings,"identity.templates.keywords.2")))
        if let catalog {
            result += (catalog.variants+catalog.work).filter {$0.localizedLine != nil}.map {
                .init(group:L10n.text(.settings,"identity.restore.text.5"),title:$0.title,kind:.interaction($0),keywords:L10n.text(.settings,"identity.templates.keywords.3"))
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
