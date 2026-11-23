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
        let open = ActionButton(L10n.text(.settings,"workspace.open")) {FinderFileReveal.openDirectory(directory)}
        let choose = ActionButton(L10n.text(.settings,"workspace.choose")) { [weak self] in self?.chooseDirectory() }
        let actions = NSStackView(views:[open,choose]); actions.spacing = 8; actions.distribution = .fill
        let restore = ActionButton(L10n.text(.settings,"workspace.restore")) { [weak self] in
            guard let self else {return}
            self.form.preferences.reset(["defaultWorkspace"]); self.reload()
        }
        restore.isEnabled = !form.preferences.string("defaultWorkspace").isEmpty
        let cleanup = SettingsFooterButton(title:clearing ? L10n.text(.settings,"workspace.cleanup") : L10n.text(.settings,"workspace.cleanup.2"),target:self,action:#selector(confirmClear))
        cleanup.bezelStyle = .rounded; cleanup.hasDestructiveAction = true; cleanup.isEnabled = !clearing
        form.group(L10n.text(.settings,"search.add.text.73"),[
            form.row(L10n.text(.settings,"search.add.text.74"),detail:directory.path,control:actions),
            form.row(L10n.text(.settings,"search.add.text.75"),control:restore),
            form.row(L10n.text(.settings,"search.add.text.76"),detail:L10n.text(.settings,"workspace.render.text.5")+LocalStorage.workspace.path,control:cleanup)
        ],symbol:"folder",detail:L10n.text(.settings,"workspace.render.text.6"))
    }
    private func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = form.preferences.defaultWorkspace; panel.prompt = L10n.text(.settings,"workspace.chooseDirectory.text")
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
        alert.messageText = L10n.text(.settings,"workspace.confirmClear.messageText")
        alert.informativeText = L10n.text(.settings,"workspace.confirmClear.informativeText")+LocalStorage.workspace.path
        alert.addButton(withTitle:L10n.text(.conversation,"chatWindow.renameConversation.button.2"))
        alert.addButton(withTitle:L10n.text(.settings,"workspace.confirmClear.button.2")).hasDestructiveAction = true
        alert.beginDangerousSheet(for:window) { [weak self] response in
            guard let self,response == .alertSecondButtonReturn else {return}
            self.clearing = true; self.reload()
            self.clear { [weak self] result in
                guard let self else {return}
                self.clearing = false; self.reload()
                if case .failure(let error) = result {showError(L10n.text(.settings,"workspace.confirmClear.error"),error)}
            }
        }
    }
}
