import AppKit
import Carbon

enum FinderAutomationPermission {
    private static let queue = DispatchQueue(label:L10n.text(.settings,"systemPermissions.queue.label"),qos:.userInitiated)
    enum State {
        case allowed, notRequested, denied, unavailable(OSStatus)
        var title:String {
            switch self {
            case .allowed:return L10n.text(.settings,"systemPermissions.allowed")
            case .notRequested:return L10n.text(.settings,"systemPermissions.notRequested")
            case .denied:return L10n.text(.settings,"systemPermissions.denied")
            case .unavailable(let code):return code == procNotFound ? L10n.text(.settings,"systemPermissions.state.text") : L10n.format(.settings,"systemPermissions.unavailable",String(describing:code))
            }
        }
    }
    static func check(ask:Bool,completion:@escaping (State) -> Void) {
        queue.async {
            let target = NSAppleEventDescriptor(bundleIdentifier:"com.apple.finder")
            let code = AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,ask)
            let state:State
            switch code {
            case noErr:state = .allowed
            case OSStatus(errAEEventWouldRequireUserConsent):state = .notRequested
            case OSStatus(errAEEventNotPermitted):state = .denied
            default:state = .unavailable(code)
            }
            DispatchQueue.main.async {completion(state)}
        }
    }
}

enum SystemPermissionSettings {
    static func open(_ pane:String) {
        let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?"+pane)!
        if !NSWorkspace.shared.open(url) {showError(L10n.text(.settings,"systemPermissions.open.error"),PetFailure(message:L10n.text(.settings,"systemPermissions.open.message")))}
    }
}

// 状态查询不请求授权；只有明确点击按钮才触发系统授权。
final class FinderPermissionControl:NSStackView {
    private let status = NSTextField(labelWithString:L10n.text(.settings,"systemPermissions.finderPermissionControl.text"))
    private var state:FinderAutomationPermission.State?
    private var checking = false
    private var button:ActionButton!
    override init(frame:NSRect) {
        super.init(frame:frame)
        orientation = .horizontal; alignment = .centerY; spacing = 8
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor
        button = ActionButton(L10n.text(.settings,"systemPermissions.button")) { [weak self] in self?.performAction() }
        addArrangedSubview(status); addArrangedSubview(button)
        NotificationCenter.default.addObserver(self,selector:#selector(refresh(_:)),name:NSWindow.didBecomeKeyNotification,object:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func viewDidMoveToWindow() {super.viewDidMoveToWindow(); if window != nil {check(ask:false)}}
    @objc private func refresh(_ note:Notification) {if note.object as? NSWindow === window {check(ask:false)}}
    private func check(ask:Bool) {
        guard !checking else {return}
        checking = true; button.isEnabled = false
        FinderAutomationPermission.check(ask:ask) { [weak self] result in
            guard let self else {return}
            self.checking = false; self.state = result; self.status.stringValue = result.title
            self.status.setAccessibilityLabel(L10n.text(.settings,"systemPermissions.check.text")+result.title)
            switch result {
            case .notRequested:self.button.title = L10n.text(.settings,"systemPermissions.button")
            case .unavailable:self.button.title = L10n.text(.settings,"systemPermissions.unavailable.2")
            default:self.button.title = L10n.text(.settings,"settingsWindow.general.button.6")
            }
            self.button.isEnabled = true
        }
    }
    private func performAction() {
        switch state {
        case .allowed?,.denied?:SystemPermissionSettings.open("Privacy_Automation")
        case .notRequested?:check(ask:true)
        default:check(ask:false)
        }
    }
}
