import Foundation
import Darwin

/// 终端开关与输出由主队列处理。桌面 IPC 工作队列仅读取当次监视实例。
final class TerminalMonitor {
    private static let development = ProcessInfo.processInfo.environment["BAILONG_DEV_RUN"] == "1"
    private static let animationDetailsOnStart = !CommandLine.arguments.contains("--no-monitor-animation")
    private static let stateLock = NSLock()
    private static var current:TerminalMonitor? = development && !CommandLine.arguments.contains("--no-monitor") ? TerminalMonitor() : nil
    static var active:TerminalMonitor? {development ? stateLock.withLock {current} : nil}
    private(set) var showsAnimation = TerminalMonitor.animationDetailsOnStart

    static func keyboard(onEnable:@escaping (TerminalMonitor) -> Void) -> DispatchSourceRead? {
        guard development,CommandLine.arguments.contains("--monitor-keys"),isatty(STDIN_FILENO) == 1 else {return nil}
        var resumeAnimation = active?.showsAnimation ?? animationDetailsOnStart
        let source = DispatchSource.makeReadSource(fileDescriptor:STDIN_FILENO,queue:.main)
        source.setEventHandler {
            var bytes = [UInt8](repeating:0,count:64)
            let count = read(STDIN_FILENO,&bytes,bytes.count)
            guard count > 0 else {if count == 0 || errno != EINTR {source.cancel()}; return}
            for byte in bytes.prefix(count) {
                switch byte {
                case 77,109: // M
                    if let monitor = active {
                        resumeAnimation = monitor.showsAnimation
                        monitor.write(.app,L10n.text(.diagnostics,"terminalMonitor.monitor.text"))
                        stateLock.withLock {current = nil}
                    } else {
                        let monitor = TerminalMonitor()
                        monitor.showsAnimation = resumeAnimation
                        stateLock.withLock {current = monitor}
                        onEnable(monitor)
                    }
                case 65,97: // A
                    if let monitor = active {
                        monitor.showsAnimation.toggle()
                        monitor.write(.app,monitor.showsAnimation ? L10n.text(.diagnostics,"terminalMonitor.monitor.text.2") : L10n.text(.diagnostics,"terminalMonitor.monitor.text.3"))
                    }
                default:break
                }
            }
        }
        source.resume()
        return source
    }

    enum Module:String {
        case app, persona, desktop, approval, server, ipc, desktopQueue, bubble, animation, history
        var title:String {
            switch self {
            case .app:return L10n.text(.diagnostics,"terminalMonitor.title.text")
            case .persona:return L10n.text(.diagnostics,"terminalMonitor.title.text.2")
            case .desktop:return L10n.text(.diagnostics,"terminalMonitor.title.text.3")
            case .approval:return L10n.text(.settings,"identity.templates.text.6")
            case .server:return "app-server"
            case .ipc:return L10n.text(.diagnostics,"terminalMonitor.title.text.4")
            case .desktopQueue:return L10n.text(.diagnostics,"terminalMonitor.title.text.5")
            case .bubble:return L10n.text(.diagnostics,"terminalMonitor.title.text.6")
            case .animation:return L10n.text(.diagnostics,"pet.play.text.2")
            case .history:return L10n.text(.diagnostics,"terminalMonitor.labels.text")
            }
        }
        var color:String? {
            switch self {
            case .server:return "1;36"
            case .ipc,.desktop,.desktopQueue:return "35"
            case .animation:return "94"
            case .bubble:return "32"
            default:return nil
            }
        }
    }
    enum Level:String {
        case info, success, warning, error
        var title:String {
            switch self {
            case .info:return L10n.text(.diagnostics,"terminalMonitor.title.text.7")
            case .success:return L10n.text(.diagnostics,"terminalMonitor.title.text.8")
            case .warning:return L10n.text(.diagnostics,"terminalMonitor.title.text.9")
            case .error:return L10n.text(.diagnostics,"terminalMonitor.title.text.10")
            }
        }
        var color:String {
            switch self {case .info:return "36"; case .success:return "32"; case .warning:return "33"; case .error:return "31"}
        }
    }
    private let clock = DateFormatter()
    private let color:Bool
    private var outputOpen = true
    private init() {
        let environment = ProcessInfo.processInfo.environment
        color = isatty(STDOUT_FILENO) == 1 && (environment["TERM"] ?? "dumb") != "dumb" && environment["NO_COLOR"] == nil
        clock.locale = Locale(identifier:"en_US_POSIX")
        clock.dateFormat = "HH:mm:ss.SSS"
        // 过滤器提前退出时让管道返回 EPIPE，桌宠继续运行。
        _ = fcntl(STDOUT_FILENO,F_SETNOSIGPIPE,1)
    }
    private func styled(_ value:String,_ code:String) -> String {color ? "\u{1B}[\(code)m\(value)\u{1B}[0m" : value}
    // 固定列只包含 ASCII 和中文标签。按终端显示宽度补真实 Tab，然后再应用 ANSI 样式。
    private func column(_ value:String,stops:Int,color code:String? = nil) -> String {
        let width = value.unicodeScalars.reduce(0) {$0 + ($1.isASCII ? 1 : 2)}
        let tabs = String(repeating:"\t",count:max(1,stops-width/8))
        return (code.map {styled(value,$0)} ?? value)+tabs
    }
    func start(version:String) {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let heading = styled(column(L10n.text(.diagnostics,"terminalMonitor.heading.text"),stops:2)+column(L10n.text(.diagnostics,"terminalMonitor.heading.text.2"),stops:1)+column(L10n.text(.diagnostics,"terminalMonitor.heading.text.3"),stops:2)+L10n.text(.diagnostics,"terminalMonitor.heading.text.4"),"1;35")
        output("\n"+heading+"\n")
        write(.app,L10n.format(.diagnostics,"terminalMonitor.heading.text.5",String(describing:version),String(describing:architecture),String(describing:ProcessInfo.processInfo.processIdentifier)))
    }
    func write(_ module:Module,_ event:String,_ level:Level = .info) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.write(module,event,level) }; return
        }
        guard self === Self.active else {return}
        let time = column(clock.string(from:Date()),stops:2,color:"2")
        let severity = column(level.title,stops:1,color:level.color)
        let source = column(module.title,stops:2,color:module.color)
        output(time+severity+source+event+"\n")
    }
    private func output(_ line:String) {
        guard outputOpen else {return}
        do {try FileHandle.standardOutput.write(contentsOf:Data(line.utf8))}
        catch {
            outputOpen = false
            fputs(L10n.text(.diagnostics,"terminalMonitor.output.text")+Self.errorCode(error)+"\n",stderr)
        }
    }
    // Swift Hasher 使用进程内随机种子，各轮次无需维护标识映射表。
    static func tag(_ key:String) -> String {String(format:"%08X",UInt32(truncatingIfNeeded:key.hashValue))}
    static func context(_ conversation:String,turn:String? = nil) -> String {
        L10n.text(.diagnostics,"terminalMonitor.context.text")+tag(conversation)+(turn.map {L10n.text(.diagnostics,"terminalMonitor.context.text.2")+tag($0)} ?? "")
    }
    static func clip(_ id:String) -> String {
        let valid = !id.isEmpty && id.utf8.count <= 40 && id.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
        return valid ? id : L10n.text(.diagnostics,"terminalMonitor.valid.text")+tag(id)
    }
    static func milliseconds(_ seconds:Double) -> String {"\(Int((seconds*1000).rounded())) ms"}
    static func errorCode(_ error:Error) -> String {
        let value = error as NSError
        let domains = [NSCocoaErrorDomain,NSPOSIXErrorDomain,NSURLErrorDomain,"AVFoundationErrorDomain","NSOSStatusErrorDomain"]
        return (domains.contains(value.domain) ? value.domain+" " : L10n.text(.diagnostics,"terminalMonitor.domains.text"))+String(value.code)
    }
    static func status(_ value:String) -> String {
        switch value {
        case "pending":return L10n.text(.conversation,"transcriptRenderer.turnStatus.text")
        case "running","inProgress":return L10n.text(.tasks,"overview.state")
        case "waitingForApproval":return L10n.text(.tasks,"taskActivity.append.text.3")
        case "waitingForInput":return L10n.text(.tasks,"taskActivity.attention")
        case "completed":return L10n.text(.tasks,"overview.state.2")
        case "failed":return L10n.text(.tasks,"overview.state.3")
        case "interrupted":return L10n.text(.tasks,"overview.state.5")
        case "cancelled","canceled":return L10n.text(.tasks,"taskActivity.failed.3")
        default:return L10n.text(.diagnostics,"terminalMonitor.labels.text.2")
        }
    }
    final class Send {
        private let monitor:TerminalMonitor, module:Module, context:String
        private let start = ProcessInfo.processInfo.systemUptime
        private var previous:TimeInterval
        fileprivate init(_ monitor:TerminalMonitor,_ module:Module,_ context:String) {
            self.monitor = monitor; self.module = module; self.context = context; previous = start
        }
        func step(_ event:String,_ level:Level = .info) {
            let now = ProcessInfo.processInfo.systemUptime
            let timing = L10n.text(.diagnostics,"terminalMonitor.timing.text")+milliseconds(now-previous)+L10n.text(.diagnostics,"terminalMonitor.timing.text.2")+milliseconds(now-start)
            monitor.write(module,context+"  "+event+"  ·  "+timing,level)
            previous = now
        }
    }
    func begin(_ module:Module,context:String,event:String) -> Send {
        let send = Send(self,module,context)
        write(module,context+"  "+event)
        return send
    }
}
