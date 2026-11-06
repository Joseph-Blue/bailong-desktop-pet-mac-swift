import AppKit

// 默认目录只影响新会话；清理入口始终绑定应用内置 Workspace。
final class WorkspaceSettingsPage:NSObject {
    private let form:SettingsForm
    private unowned let window:NSWindow
    private let reload:() -> Void
    private let clear:(@escaping (Result<Void,Error>) -> Void) -> Void
    private var clearing = false
    init(form:SettingsForm,window:NSWindow,reload:@escaping () -> Void,clear:@escaping (@escaping (Result<Void,Error>) -> Void) -> Void) {
        self.form = form; self.window = window; self.reload = reload; self.clear = clear
    }
    func render() {
        let directory = form.preferences.defaultWorkspace
        let open = ActionButton("在访达中打开") {FinderFileReveal.openDirectory(directory)}
        let choose = ActionButton("选择目录…") { [weak self] in self?.chooseDirectory() }
        let actions = NSStackView(views:[open,choose]); actions.spacing = 8; actions.distribution = .fill
        let restore = ActionButton("恢复内置目录") { [weak self] in
            guard let self else {return}
            self.form.preferences.reset(["defaultWorkspace"]); self.reload()
        }
        restore.isEnabled = !form.preferences.string("defaultWorkspace").isEmpty
        let cleanup = SettingsFooterButton(title:clearing ? "正在清理…" : "清理…",target:self,action:#selector(confirmClear))
        cleanup.bezelStyle = .rounded; cleanup.hasDestructiveAction = true; cleanup.isEnabled = !clearing
        form.group("桌宠对话默认工作区",[
            form.row("默认工作区",detail:directory.path,control:actions),
            form.note("“在默认工作区新建”使用此目录；已有会话保留各自的工作区，更改目录不搬移文件。"),
            form.row("恢复内置工作区",control:restore),
            form.row("清理内置工作区",detail:"仅将下方内置目录的内容移到废纸篓，保留目录和聊天记录。自定义工作区不清理。\n"+LocalStorage.workspace.path,control:cleanup)
        ])
    }
    private func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = form.preferences.defaultWorkspace; panel.prompt = "设为默认工作区"
        PanelPresentation.present(panel,relativeTo:window) { [weak self] response in
            guard let self,response == .OK,let directory = panel.url else {return}
            let path = directory.standardizedFileURL.path
            self.form.preferences.set(path == LocalStorage.workspace.path ? "" : path,for:"defaultWorkspace")
            self.reload()
        }
    }
    @objc private func confirmClear() {
        guard !clearing else {return}
        window.makeFirstResponder(nil)
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "清理内置工作区？"
        alert.informativeText = "将此目录中的全部文件和子文件夹移到废纸篓，包括隐藏文件。保留目录和聊天记录；历史中的文件链接将无法在原位置打开。\n\n"+LocalStorage.workspace.path
        alert.addButton(withTitle:"取消")
        alert.addButton(withTitle:"移到废纸篓").hasDestructiveAction = true
        alert.beginDangerousSheet(for:window) { [weak self] response in
            guard let self,response == .alertSecondButtonReturn else {return}
            self.clearing = true; self.reload()
            self.clear { [weak self] result in
                guard let self else {return}
                self.clearing = false; self.reload()
                if case .failure(let error) = result {showError("工作区清理未完成",error)}
            }
        }
    }
}
