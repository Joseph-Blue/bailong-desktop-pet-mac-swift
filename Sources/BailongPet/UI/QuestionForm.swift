import AppKit

private final class QuestionOptionLabel:NSTextField {
    var select:() -> Void = {}
    override func mouseDown(with event:NSEvent) {select()}
}

// 草稿及跳过状态仅保存在当前请求内存中，不写入历史。
final class QuestionForm: NSView {
    let questions:[TaskQuestion]
    private var scale:CGFloat, fontSize:CGFloat
    private var selected = [String:String](), skipped = Set<String>()
    private var radios = [NSButton](), inputs = [MessageEditor](), editors = [MessageInputBox]()
    private var generated = [NSView]()
    private weak var pageLabel:NSTextField?
    private var enabled = true
    private(set) var currentIndex = 0
    var onChange: () -> Void = {}, onNavigate: () -> Void = {}, onSubmit: () -> Void = {}, onSkipAll: () -> Void = {}
    var skippedIDs:Set<String> {skipped}
    var canGoBack:Bool {enabled && currentIndex > 0}
    var canSkip:Bool {enabled}
    override var isFlipped:Bool {true}
    private func answer(at index:Int) -> String {
        let q = questions[index]
        return [selected[q.id] ?? "",inputs[index].string.trimmingCharacters(in:.whitespacesAndNewlines)]
            .filter {!$0.isEmpty}.joined(separator:"\n")
    }
    var answers:[String:String] {
        var result = [String:String]()
        for (i,q) in questions.enumerated() where !skipped.contains(q.id) {
            let value = answer(at:i); if !value.isEmpty {result[q.id] = value}
        }
        return result
    }
    var isLast:Bool {currentIndex == questions.count-1}
    var complete:Bool {isLast && questions.enumerated().allSatisfy {skipped.contains($0.element.id) || !answer(at:$0.offset).isEmpty}}
    var actionTitle:String {isLast ? (answers.isEmpty && complete ? "关闭" : "提交回答") : "下一题"}
    var canAdvance:Bool {enabled && (isLast ? complete : !answer(at:currentIndex).isEmpty || skipped.contains(questions[currentIndex].id))}
    init(questions:[TaskQuestion],width:CGFloat,scale:CGFloat,fontSize:CGFloat) {
        self.questions = questions; self.scale = scale; self.fontSize = fontSize
        super.init(frame:NSRect(x:0,y:0,width:width,height:0))
        for (qi,q) in questions.enumerated() {
            for oi in 0..<(q.options.isEmpty ? 0 : q.options.count+1) {
                let button = AccentChoiceButton(title:"",type:.radio); button.target = self; button.action = #selector(selectOption(_:))
                button.identifier = .init(q.id); button.tag = qi*1000+oi
                button.setAccessibilityLabel(oi < q.options.count ? q.options[oi].title : "其他"); radios.append(button)
            }
            let input = MessageEditor(frame:NSRect(x:0,y:0,width:width,height:80*scale))
            input.placeholder = q.options.isEmpty ? "输入回答" : "其他回答或补充说明"
            input.font = .systemFont(ofSize:fontSize); input.textColor = .labelColor; input.backgroundColor = .textBackgroundColor
            input.isRichText = false; input.allowsUndo = true
            input.isAutomaticQuoteSubstitutionEnabled = false; input.isAutomaticDashSubstitutionEnabled = false
            input.isVerticallyResizable = true; input.isHorizontallyResizable = false; input.autoresizingMask = [.width]
            input.textContainer?.widthTracksTextView = true
            input.textContainer?.containerSize = NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)
            input.textContainerInset = NSSize(width:6*scale,height:6*scale)
            input.minSize = .zero; input.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
            input.setAccessibilityLabel(q.prompt+"：输入回答")
            input.onTextChange = { [weak self] in self?.changedInput(qi) }
            input.send = { [weak self] in self?.advance() }
            let scroll = GutterScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
            scroll.drawsBackground = false; scroll.documentView = input
            let box = MessageInputBox(scroll:scroll,editor:input)
            inputs.append(input); editors.append(box); addSubview(box)
        }
        reflow(width:width)
    }
    required init?(coder:NSCoder) {fatalError()}
    func restoreDrafts(from previous:QuestionForm) {
        for (index,q) in questions.enumerated() {
            guard let oldIndex = previous.questions.firstIndex(where:{$0.id == q.id && $0.prompt == q.prompt}) else {continue}
            inputs[index].string = previous.inputs[oldIndex].string
            if let value = previous.selected[q.id],q.options.contains(where:{$0.title == value}) {selected[q.id] = value}
            if previous.skipped.contains(q.id) {skipped.insert(q.id)}
            for button in radios where button.identifier?.rawValue == q.id {
                let option = button.tag % 1000
                button.state = option < q.options.count ? (selected[q.id] == q.options[option].title ? .on : .off) :
                    (selected[q.id] == nil && !inputs[index].string.isEmpty ? .on : .off)
            }
        }
        if previous.questions.indices.contains(previous.currentIndex),
           let index = questions.firstIndex(where:{$0.id == previous.questions[previous.currentIndex].id}) {currentIndex = index}
    }
    func updateAppearance(scale:CGFloat,fontSize:CGFloat) {
        self.scale = scale; self.fontSize = fontSize
        for input in inputs {input.font = .systemFont(ofSize:fontSize)}
    }
    func reflow(width:CGFloat) {
        for view in generated {view.removeFromSuperview()}; generated.removeAll()
        for button in radios {button.isHidden = true}
        for (i,editor) in editors.enumerated() {editor.isHidden = i != currentIndex}
        guard !questions.isEmpty else {return}
        let inset = 5*scale, usable = max(100,width-inset*2), qi = currentIndex, q = questions[qi]
        var y = 5*scale
        func add(_ view:NSView) {addSubview(view); generated.append(view)}
        func text(_ value:String,_ size:CGFloat,_ width:CGFloat,_ secondary:Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString:value); field.font = .systemFont(ofSize:size)
            field.textColor = secondary ? .secondaryLabelColor : .labelColor
            field.frame.size = NSSize(width:width,height:ceil(field.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:100000)).height))
            return field
        }
        let page = text("第 \(qi+1) / \(questions.count) 题"+(skipped.contains(q.id) ? " · 已跳过" : ""),11*scale,usable,true)
        pageLabel = page; page.frame.origin = NSPoint(x:inset,y:y); add(page); y += page.frame.height+10*scale
        let prompt = text(q.prompt,fontSize,usable); prompt.frame.origin = NSPoint(x:inset,y:y); add(prompt); y += prompt.frame.height+8*scale
        for (oi,option) in q.options.enumerated() {
            let button = radios.first {$0.tag == qi*1000+oi}!
            let x = inset+24*scale
            let name = QuestionOptionLabel(wrappingLabelWithString:"\(oi+1). "+option.title+(option.recommended ? "（推荐）" : ""))
            name.font = .systemFont(ofSize:fontSize)
            name.frame.size = NSSize(width:usable-24*scale,height:ceil(name.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:usable-24*scale,height:100000)).height))
            name.select = { [weak button] in button?.performClick(nil) }
            name.frame.origin = NSPoint(x:x,y:y)
            button.frame = NSRect(x:inset,y:y,width:20*scale,height:20*scale); button.isHidden = false; addSubview(button)
            add(name); y += max(20*scale,name.frame.height)
            if let detail = option.detail,!detail.isEmpty {
                let field = text(detail,max(10*scale,fontSize-2*scale),usable-24*scale,true)
                field.frame.origin = NSPoint(x:x,y:y+3*scale); add(field); y += field.frame.height+3*scale
            }
            y += 8*scale
        }
        if !q.options.isEmpty {
            let button = radios.first {$0.tag == qi*1000+q.options.count}!
            button.title = "其他"; button.font = .systemFont(ofSize:fontSize)
            button.frame = NSRect(x:inset,y:y,width:usable,height:24*scale); button.isHidden = false; addSubview(button); y += 28*scale
        }
        let editor = editors[qi]; editor.frame = NSRect(x:inset,y:y,width:usable,height:80*scale)
        editor.layoutSubtreeIfNeeded()
        let input = inputs[qi]; input.frame.size.width = editor.contentSize.width
        input.textContainer?.containerSize.width = editor.contentSize.width
        input.minSize.height = editor.contentSize.height
        input.frame.size.height = max(input.frame.height,editor.contentSize.height); y += editor.frame.height+8*scale
        let shortcut = PetPreferences.shared.sendShortcut
        let hint = text("\(isLast ? "提交" : "下一题")：\(shortcut.sendLabel)\n换行：\(shortcut.newlineLabel)",11*scale,usable,true)
        hint.frame.origin = NSPoint(x:inset,y:y); add(hint); y += hint.frame.height+10*scale
        frame.size = NSSize(width:width,height:y+5*scale)
        window?.invalidateCursorRects(for:self)
    }

    private func navigate(to index:Int) {
        window?.makeFirstResponder(nil); currentIndex = index; onNavigate(); onChange()
    }
    func previousPage() {if enabled && currentIndex > 0 {navigate(to:currentIndex-1)}}
    func skipPage() {
        guard enabled else {return}
        skipped.insert(questions[currentIndex].id)
        if !isLast {navigate(to:currentIndex+1)} else if answers.isEmpty {onSkipAll()} else {onNavigate(); onChange()}
    }
    func advance() {
        guard canAdvance else {return}
        if isLast {onSubmit()} else {navigate(to:currentIndex+1)}
    }
    @objc private func selectOption(_ sender:NSButton) {
        guard enabled else {return}
        let qi = sender.tag/1000, oi = sender.tag%1000, q = questions[qi]
        skipped.remove(q.id); refreshPageLabel(); selected[q.id] = oi < q.options.count ? q.options[oi].title : nil
        inputs[qi].placeholder = oi < q.options.count ? "补充说明（可选）" : "输入回答"
        for button in radios where button.identifier == sender.identifier {button.state = button === sender ? .on : .off}
        onChange()
    }
    private func changedInput(_ index:Int) {
        let q = questions[index]; skipped.remove(q.id); refreshPageLabel()
        if selected[q.id] == nil,!q.options.isEmpty {
            radios.first {$0.tag == index*1000+q.options.count}?.state = inputs[index].string.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? .off : .on
        }
        onChange()
    }
    private func refreshPageLabel() {
        pageLabel?.stringValue = "第 \(currentIndex+1) / \(questions.count) 题"+(skipped.contains(questions[currentIndex].id) ? " · 已跳过" : "")
    }
    func setEnabled(_ value:Bool) {
        enabled = value
        for radio in radios {radio.isEnabled = value}
        for input in inputs {input.isEditable = value}
        for button in generated.compactMap({$0 as? NSButton}) {button.isEnabled = value && (button.title != "上一题" || currentIndex > 0)}
    }
}

final class QuestionResizeDelegate: NSObject, NSWindowDelegate {
    var resized: () -> Void = {}
    func windowDidResize(_ notification:Notification) {
        guard let window = notification.object as? NSWindow,window.inLiveResize else {return}
        resized()
    }
}
