import AppKit
import Carbon

enum FinderAutomationPermission {
    private static let queue = DispatchQueue(label:"白龙桌宠 访达授权",qos:.userInitiated)
    enum State {
        case allowed, notRequested, denied, unavailable(OSStatus)
        var title:String {
            switch self {
            case .allowed:return "已允许"
            case .notRequested:return "尚未授权"
            case .denied:return "未允许"
            case .unavailable(let code):return code == procNotFound ? "访达未运行" : "状态读取失败（\(code)）"
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
        if !NSWorkspace.shared.open(url) {showError("无法打开系统设置",PetFailure(message:"请打开系统设置 → 隐私与安全性。"))}
    }
}

// 状态查询不请求授权；只有明确点击按钮才触发系统授权。
final class FinderPermissionControl:NSStackView {
    private let status = NSTextField(labelWithString:"正在检查…")
    private var state:FinderAutomationPermission.State?
    private var checking = false
    private var button:ActionButton!
    override init(frame:NSRect) {
        super.init(frame:frame)
        orientation = .horizontal; alignment = .centerY; spacing = 8
        status.font = .systemFont(ofSize:11); status.textColor = .secondaryLabelColor
        button = ActionButton("授权…") { [weak self] in self?.performAction() }
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
            self.status.setAccessibilityLabel("访达自动化："+result.title)
            switch result {
            case .notRequested:self.button.title = "授权…"
            case .unavailable:self.button.title = "重新检查"
            default:self.button.title = "系统设置…"
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
