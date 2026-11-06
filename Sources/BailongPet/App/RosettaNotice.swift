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
                NSLog("Rosetta 运行状态检测失败：%@", NSError(domain:NSPOSIXErrorDomain,code:Int(code)).localizedDescription)
            }
            return true
        }
        guard translated == 1 else {return true}

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "你的 Mac 应使用 Apple Silicon 版"
        alert.informativeText = "当前打开的是 Intel 版，正在通过 Rosetta 转译运行。强烈建议改用 Apple Silicon 原生版。\n\n请在发布页下载文件名以 macos-apple-silicon.zip 结尾的安装包。"
        alert.addButton(withTitle:"前往下载并退出")
        alert.addButton(withTitle:"仍要运行 Intel 版")
        alert.addButton(withTitle:"退出").keyEquivalent = "\u{1b}"
        alert.applyAccent()
        NSApp.activate(ignoringOtherApps:true)
        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let url = UpdateChecker.releases.appendingPathComponent("latest")
                if NSWorkspace.shared.open(url) {return false}
                showError("无法打开发布页",PetFailure(message:url.absoluteString))
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
