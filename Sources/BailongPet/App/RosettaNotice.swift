import AppKit
import Darwin

enum RosettaNotice {
    // 只提示已经通过 Rosetta 启动的 Intel 主程序；原生运行及跟随助手不弹窗。
    static func confirmLaunch() -> Bool {
        #if arch(x86_64)
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 else {
            let code = errno
            // Intel Mac 没有这个键；其他查询错误保留实际诊断，不据此宣称架构。
            if code != ENOENT {
                NSLog(L10n.text(.diagnostics,"rosettaNotice.code.text"), NSError(domain:NSPOSIXErrorDomain,code:Int(code)).localizedDescription)
            }
            return true
        }
        guard translated == 1 else {return true}

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text(.diagnostics,"rosettaNotice.confirmLaunch.messageText")
        alert.informativeText = L10n.text(.diagnostics,"rosettaNotice.confirmLaunch.informativeText")
        alert.addButton(withTitle:L10n.text(.diagnostics,"rosettaNotice.confirmLaunch.button"))
        alert.addButton(withTitle:L10n.text(.diagnostics,"rosettaNotice.confirmLaunch.button.2"))
        alert.addButton(withTitle:L10n.text(.diagnostics,"rosettaNotice.confirmLaunch.button.3")).keyEquivalent = "\u{1b}"
        alert.applyAccent()
        NSApp.activate(ignoringOtherApps:true)
        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let url = UpdateChecker.releases.appendingPathComponent("latest")
                if NSWorkspace.shared.open(url) {return false}
                showError(L10n.text(.diagnostics,"rosettaNotice.confirmLaunch.error"),PetFailure(message:url.absoluteString))
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
        #else
        return true
        #endif
    }
}
