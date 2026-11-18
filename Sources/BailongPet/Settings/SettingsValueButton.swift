import AppKit

// 值始终显示在设置行内，只有打开时才建立并持有编辑表单。
final class SettingsValueButton:NSButton,NSPopoverDelegate {
    private let makeEditor:(SettingsForm) -> Void
    private let preferences:PetPreferences
    private var popover:NSPopover?
    init(label:String,preferences:PetPreferences,makeEditor:@escaping (SettingsForm) -> Void) {
        self.preferences = preferences; self.makeEditor = makeEditor
        super.init(frame:.zero)
        bezelStyle = .rounded; controlSize = .small
        image = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil)
        imagePosition = .imageTrailing; target = self; action = #selector(toggleEditor)
        setAccessibilityLabel(label); identifier = .init("setting:"+label)
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func toggleEditor() {
        if popover?.isShown == true {closeEditor()} else {showEditor()}
    }
    func showEditor(focusing title:String? = nil) {
        guard isEnabled,let window,window.isVisible,!isHiddenOrHasHiddenAncestor else {return}
        let controller:ValueEditor
        if let existing = popover?.contentViewController as? ValueEditor {controller = existing}
        else {
            controller = ValueEditor(window:window,preferences:preferences,build:makeEditor)
            let panel = NSPopover(); panel.behavior = .transient; panel.animates = DisclosureMotion.enabled
            panel.delegate = self; panel.contentViewController = controller; panel.contentSize = controller.preferredContentSize
            popover = panel; panel.show(relativeTo:bounds,of:self,preferredEdge:.minY)
        }
        if let title {controller.focus(title)}
    }
    func closeEditor() {popover?.close()}
    func popoverDidClose(_ notification:Notification) {popover = nil}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); if window == nil {closeEditor()}}
    override func viewDidHide() {super.viewDidHide(); closeEditor()}
}

private final class ValueEditor:NSViewController {
    private let stack = NSStackView(), form:SettingsForm
    init(window:NSWindow,preferences:PetPreferences,build:(SettingsForm) -> Void) {
        form = SettingsForm(content:stack,preferences:preferences,window:window)
        super.init(nibName:nil,bundle:nil)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        view = NSView(); view.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:14),
            stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-14),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:12),
            stack.bottomAnchor.constraint(equalTo:view.bottomAnchor,constant:-12)])
        build(form)
        preferredContentSize = view.fittingSize
    }
    required init?(coder:NSCoder) {fatalError()}
    func focus(_ title:String) {
        func input(in view:NSView) -> NSControl? {
            if let control = view as? NSControl,control.acceptsFirstResponder,control.accessibilityLabel() == title {return control}
            for child in view.subviews {if let found = input(in:child) {return found}}
            return nil
        }
        if let control = input(in:stack) {view.window?.makeFirstResponder(control)}
    }
}
