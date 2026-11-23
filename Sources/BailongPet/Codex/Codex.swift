import AppKit

final class CodexConnection {
    typealias Reply = (Result<[String:Any],Error>) -> Void
    var event: (String,[String:Any]) -> Void = { _,_ in }
    var request: (Any,String,[String:Any]) -> Void = { _,_,_ in }
    var disconnected: (Error) -> Void = { _ in }
    private var process: Process?
    private var input: FileHandle?
    private var serial = 0
    private struct PendingCall {
        let reply:Reply, method:String, deadline:Date
        let started = ProcessInfo.processInfo.systemUptime
        var elapsed:String {TerminalMonitor.milliseconds(ProcessInfo.processInfo.systemUptime-started)}
    }
    private var pending = [Int:PendingCall]()
    private var waiting = [(Error?) -> Void]()
    private var ready = false
    struct PreparedThread {
        let id:String, provider:String?, model:String?, effort:String?
    }
    private var loadedThreads = [String:PreparedThread]()
    private var closing = false
    private var generation = 0
    private var expiration: Timer?
    private let reader = DispatchQueue(label:L10n.text(.tasks,"codex.reader.label"))
    private var connectionError: String?
    private var cliVersion: String?
    private(set) var executableURL: URL?
    var isConnected:Bool {ready}
    var connectionGeneration:Int {generation}
    func reportMonitorState(to monitor:TerminalMonitor) {
        let state = ready ? L10n.text(.conversation,"codex.state") : process == nil ? L10n.text(.conversation,"codex.state.2") : L10n.text(.conversation,"codex.state.3")
        let pid = process.map {"  ·  PID \($0.processIdentifier)"} ?? ""
        monitor.write(.server,L10n.text(.tasks,"codex.pid.text")+state+pid+L10n.format(.tasks,"codex.pid.text.2",String(describing:pending.count),String(describing:loadedThreads.count)))
        for (id,call) in pending.sorted(by:{$0.key < $1.key}) {
            monitor.write(.server,L10n.text(.tasks,"codex.pid.text.3")+TerminalMonitor.rpcName(call.method)+L10n.format(.tasks,"codex.pid.text.4",String(describing:id))+call.elapsed)
        }
    }
    var diagnostics: String {
        let state = ready ? L10n.text(.conversation,"codex.state.4") : process?.isRunning == true ? L10n.text(.conversation,"codex.state.5") : (connectionError.map { L10n.text(.conversation,"codex.reportMonitorState.text") + $0 } ?? L10n.text(.conversation,"codex.state.2"))
        let pid = process.map { $0.isRunning ? String($0.processIdentifier) : L10n.text(.conversation,"codex.reportMonitorState.text.2") } ?? L10n.text(.conversation,"codex.reportMonitorState.text.2")
        let version = cliVersion ?? installedCLIVersion()
        return L10n.format(.conversation,"codex.reportMonitorState.text.3",String(describing:version),String(describing:state),String(describing:executableURL?.lastPathComponent ?? "codex"),String(describing:pid),String(describing:pending.count),String(describing:executableURL?.path ?? L10n.text(.conversation,"codex.reportMonitorState.text.4")))
    }
    private static func isDesktopApplication(_ app:NSRunningApplication) -> Bool {
        !app.isTerminated && (app.bundleIdentifier == "com.openai.codex" || ["Codex","ChatGPT"].contains(app.localizedName ?? ""))
    }
    private static let installedDesktopLocations = ["/Applications/Codex.app",NSHomeDirectory()+"/Applications/Codex.app",
        "/Applications/ChatGPT.app",NSHomeDirectory()+"/Applications/ChatGPT.app"].map {URL(fileURLWithPath:$0)}
    static func desktopApplications() -> [URL] {
        NSWorkspace.shared.runningApplications.filter(isDesktopApplication).compactMap(\.bundleURL) + installedDesktopLocations
    }
    struct DesktopVersion:Equatable {
        let number:String
        let build:String?
        var display:String {number + (build.map {" ("+$0+")"} ?? "")}
        init?(_ url:URL) {
            guard let info = CFBundleCopyInfoDictionaryForURL(url as CFURL) as? [String:Any],
                  let number = info["CFBundleShortVersionString"] as? String else {return nil}
            self.number = number; build = info["CFBundleVersion"] as? String
        }
    }
    static func detectDesktopVersion() -> DesktopVersion? {
        for url in desktopApplications() {
            if let version = DesktopVersion(url) {return version}
        }
        return nil
    }
    static var desktopDiagnostics:String {
        func summary(_ url:URL?,name:String,status:String) -> String {
            let version = url.flatMap(DesktopVersion.init)?.display ?? L10n.text(.diagnostics,"resources.failure")
            return "\(name) \(version) · \(status)"
        }
        let running = NSWorkspace.shared.runningApplications.filter(isDesktopApplication)
        if !running.isEmpty {
            return running.map { summary($0.bundleURL,name:$0.localizedName ?? "Codex",status:"PID \($0.processIdentifier)") }.joined(separator:"、")
        }
        guard let url = installedDesktopLocations.first(where:{FileManager.default.fileExists(atPath:$0.path)}) else {return L10n.text(.conversation,"codex.summary.text")}
        return summary(url,name:url.deletingPathExtension().lastPathComponent,status:L10n.text(.conversation,"codex.reportMonitorState.text.2"))
    }
    private static func versionFromUserAgent(_ agent:String?) -> String? {
        guard let product = agent?.components(separatedBy:" (").first,let slash = product.lastIndex(of:"/") else {return nil}
        let version = String(product[product.index(after:slash)...])
        return SemanticVersion(version) == nil ? nil : version
    }
    static let packagedCLI = "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    private func installedCLIVersion() -> String {
        struct Package:Decodable {let version:String}
        do {
            let selected = try (executableURL ?? Self.executable()).resolvingSymlinksInPath()
            guard let app = Self.desktopApplications().first(where:{
                $0.appendingPathComponent(Self.packagedCLI).resolvingSymlinksInPath() == selected
            }) else {return ready ? L10n.text(.conversation,"codex.package.text") : L10n.text(.conversation,"codex.package.text.2")}
            let manifest = app.appendingPathComponent("Contents/Resources/codex-cli/codex-package.json")
            let package = try JSONDecoder().decode(Package.self,from:Data(contentsOf:manifest))
            return L10n.text(.conversation,"codex.package.text.3") + package.version
        } catch {return L10n.text(.conversation,"codex.package.text.4") + error.localizedDescription}
    }
    static func executable() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["BAILONG_CODEX_BIN"], !explicit.isEmpty {
            guard FileManager.default.isExecutableFile(atPath:explicit) else {throw PetFailure(message:L10n.text(.conversation,"codex.executable.message")+explicit)}
            return URL(fileURLWithPath:explicit)
        }
        // 优先当前桌面应用内置版本，防止旧 PATH CLI 不支持桌面端当前模型。
        let bundled = desktopApplications().flatMap { app in
            [packagedCLI,
             "Contents/Resources/codex", "Contents/Resources/codex-cli/codex"].map {app.appendingPathComponent($0).path}
        }
        let candidates = bundled + (env["PATH"] ?? "").split(separator:":").map {String($0)+"/codex"} +
            [NSHomeDirectory()+"/.local/bin/codex","/opt/homebrew/bin/codex","/usr/local/bin/codex"]
        guard let path = candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else {
            throw PetFailure(message:L10n.text(.conversation,"codex.executable.message.2"))
        }
        return URL(fileURLWithPath:path)
    }
    static func openDesktop() {
        guard let app = desktopApplications().first(where:{FileManager.default.fileExists(atPath:$0.path)}) else {return}
        NSWorkspace.shared.open(app)
    }
    private static let navigationQueue = DispatchQueue(label:L10n.text(.tasks,"codex.navigationQueue.label"),qos:.userInitiated)
    static func openConversation(_ id:String?) {
        guard let id,let url = threadURL(id) else {openDesktop(); return}
        navigationQueue.async {
            let lookup = Result {try DesktopHistoryReader.containsThread(id)}
            DispatchQueue.main.async {
                switch lookup {
                case .success(true):
                    if !NSWorkspace.shared.open(url) {openDesktop()}
                default:
                    // 会话已删除或本机索引不可读时，只打开桌面端。
                    openDesktop()
                }
            }
        }
    }
    static func threadURL(_ id: String) -> URL? {
        guard !id.isEmpty else {return nil}
        var url = URLComponents(); url.scheme = "codex"; url.host = "threads"; url.path = "/"+id
        return url.url
    }
    // 仅用于用户主动发送后的会话准备；成功值表示本次是否处于冷启动阶段，失败不降级到首页。
    static func openConversationForReply(_ id:String,isCurrent:@escaping () -> Bool,completion:@escaping (Result<Bool,Error>) -> Void) {
        navigationQueue.async {
            let lookup = Result {try DesktopHistoryReader.containsThread(id)}
            DispatchQueue.main.async {
                guard isCurrent() else {return}
                do {
                    guard try lookup.get(),let url = threadURL(id) else {throw PetFailure(message:L10n.text(.conversation,"codex.openConversationForReply.message"))}
                    let workspace = NSWorkspace.shared
                    let desktopID = "com.openai.codex"
                    let running = NSRunningApplication.runningApplications(withBundleIdentifier:desktopID).first {!$0.isTerminated}
                    guard let app = running?.bundleURL ?? workspace.urlForApplication(withBundleIdentifier:desktopID)
                            ?? installedDesktopLocations.first(where:{Bundle(url:$0)?.bundleIdentifier == desktopID}) else {
                        throw PetFailure(message:L10n.text(.conversation,"codex.openConversationForReply.message.2"))
                    }
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    let coldStart = running == nil || (running?.launchDate.map {Date().timeIntervalSince($0) < 10} == true)
                    NSWorkspace.shared.open([url],withApplicationAt:app,configuration:configuration) { _,error in
                        DispatchQueue.main.async {
                            if let error {completion(.failure(error))}
                            else {completion(.success(coldStart))}
                        }
                    }
                } catch {completion(.failure(error))}
            }
        }
    }
    // 冷启动账户窗口替换会清空首窗待发路由；仅对仍在运行的桌面端后台补投递原会话链接。
    static func reopenConversationForReply(_ id:String,isCurrent:@escaping () -> Bool) {
        guard isCurrent(),let url = threadURL(id),
              let app = NSWorkspace.shared.runningApplications.first(where:isDesktopApplication)?.bundleURL else {return}
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open([url],withApplicationAt:app,configuration:configuration,completionHandler:nil)
    }
    func connect(_ callback: @escaping (Error?) -> Void) {
        if ready { callback(nil); return }
        waiting.append(callback)
        if process?.isRunning == true { return }
        do {
            connectionError = nil; cliVersion = nil; closing = false; generation += 1; let token = generation
            let task = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            task.executableURL = try Self.executable(); executableURL = task.executableURL; task.arguments = ["app-server","--listen","stdio://"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = [task.executableURL!.deletingLastPathComponent().path, NSHomeDirectory()+"/.local/bin","/opt/homebrew/bin","/usr/local/bin",env["PATH"] ?? ""].joined(separator:":")
            task.environment = env; task.standardInput = stdin; task.standardOutput = stdout; task.standardError = stderr
            // 消费 stderr 防止子进程阻塞；不保存原始诊断流或用户对话日志。
            stderr.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
            try task.run(); process = task; input = stdin.fileHandleForWriting
            TerminalMonitor.active?.write(.server,L10n.format(.tasks,"codex.labels.text",String(describing:task.processIdentifier),String(describing:token)))
            reader.async { [weak self] in
                var buffer = Data()
                while true {
                    let part = stdout.fileHandleForReading.availableData
                    if part.isEmpty { break }; buffer.append(part)
                    while let end = buffer.firstIndex(of:10) {
                        let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                        do {
                            let message = try autoreleasepool {try CodexProtocol.delivery(CodexProtocol.object(line))}
                            if let message {DispatchQueue.main.async { if self?.generation == token { self?.receive(message) } }}
                        } catch { DispatchQueue.main.async { if self?.generation == token { self?.fail(error,stage:L10n.text(.conversation,"codex.connect.text")) } }; return }
                    }
                }
                // 先交付最后一条完成/错误消息，再处理 EOF，避免退出回调抢先丢失结果。
                DispatchQueue.main.async {
                    guard let self, self.generation == token, !self.closing else {return}
                    self.fail(PetFailure(message:L10n.text(.conversation,"codex.connect.message")),stage:L10n.text(.conversation,"codex.connect.error"))
                }
            }
            expiration?.invalidate()
            expiration = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
                guard let self else{return}
                let expired = self.pending.filter { $0.value.deadline < Date() }
                for (id,_) in expired {
                    guard let call = self.pending.removeValue(forKey:id) else {continue}
                    TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.call.text")+TerminalMonitor.rpcName(call.method)+"  ·  RPC#\(id)  ·  "+call.elapsed,.error)
                    call.reply(.failure(CodexProtocol.Failure.timeout))
                }
            }
            call("initialize",["clientInfo":["name":"bailong_appkit","title":PetPreferences.shared.appName,"version":Paths.version],"capabilities":["experimentalApi":true]]) { [weak self] result in
                guard let self,self.generation == token else{return}
                switch result {
                case .success(let reply):
                    guard self.send(["method":"initialized"]) else {return}; self.ready = true
                    self.cliVersion = Self.versionFromUserAgent(reply["userAgent"] as? String)
                    TerminalMonitor.active?.write(.server,L10n.format(.tasks,"codex.reply.text",String(describing:token)),.success)
                    let callbacks = self.waiting; self.waiting.removeAll(); callbacks.forEach{$0(nil)}
                case .failure(let error): self.fail(error,stage:L10n.text(.conversation,"codex.failure"))
                }
            }
        } catch { fail(error,stage:L10n.text(.conversation,"codex.connect.text.2")) }
    }
    // 同一服务进程内复用已加载的会话；恢复只用于本次连接尚未加载的历史会话。
    func prepareThread(_ id:String?,params:[String:Any],completion:@escaping (Result<PreparedThread,Error>) -> Void) {
        if let id,let prepared = loadedThreads[id] {
            TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.prepared.text")+TerminalMonitor.tag(id))
            completion(.success(prepared)); return
        }
        var params = params
        if let id {params["threadId"] = id}
        call(id == nil ? "thread/start" : "thread/resume",params) { [weak self] result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let value):
                guard let thread = value["thread"] as? [String:Any],let id = thread["id"] as? String,!id.isEmpty else {
                    completion(.failure(CodexProtocol.Failure.malformed(L10n.text(.conversation,"codex.prepareThread.text")))); return
                }
                let prepared = PreparedThread(id:id,provider:value["modelProvider"] as? String ?? thread["modelProvider"] as? String,
                    model:value["model"] as? String,effort:value["reasoningEffort"] as? String)
                self?.loadedThreads[id] = prepared
                completion(.success(prepared))
            }
        }
    }
    func call(_ method: String, _ params: [String:Any], completion: @escaping Reply) {
        guard input != nil else {
            TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.call.text.2")+TerminalMonitor.rpcName(method)+L10n.text(.tasks,"codex.call.text.3"),.warning)
            completion(.failure(CodexProtocol.Failure.disconnected)); return
        }
        serial += 1
        pending[serial] = PendingCall(reply:completion,method:method,deadline:Date().addingTimeInterval(30))
        if send(["id":serial,"method":method,"params":params]) {
            TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.labels.text.2")+TerminalMonitor.rpcName(method)+"  ·  RPC#\(serial)"+TerminalMonitor.rpcFields(params))
        }
    }
    func reply(_ id: Any, _ result: [String:Any]) {
        if send(["id":id,"result":result]) {TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.reply.text.2")+TerminalMonitor.serverRequestID(id))}
    }
    func unsupported(_ id: Any, _ method: String) {
        if send(["id":id,"error":["code":-32601,"message":L10n.format(.conversation,"codex.unsupported.text",String(describing:method))]]) {
            TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.reply.text.2")+TerminalMonitor.serverRequestID(id)+L10n.text(.tasks,"codex.unsupported.text"),.warning)
        }
    }
    @discardableResult private func send(_ value:[String:Any]) -> Bool {
        do {
            guard let input else {throw CodexProtocol.Failure.disconnected}
            var bytes = try JSONSerialization.data(withJSONObject:value); bytes.append(10)
            try input.write(contentsOf:bytes); return true
        } catch {fail(error,stage:L10n.text(.conversation,"codex.send.text")); return false}
    }
    func abortUnconfirmedTask() {
        fail(PetFailure(message:L10n.text(.conversation,"codex.abortUnconfirmedTask.message")))
    }
    func reject(_ id:Any,_ message:String) {
        if send(["id":id,"error":["code":-32602,"message":message]]) {
            TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.reply.text.2")+TerminalMonitor.serverRequestID(id)+L10n.text(.tasks,"codex.reject.text"),.warning)
        }
    }
    private func receive(_ value: [String:Any]) {
        if let method = value["method"] as? String {
            if let id = value["id"] {
                TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.id.text")+TerminalMonitor.rpcName(method)+L10n.text(.tasks,"codex.id.text.2")+TerminalMonitor.serverRequestID(id)
                    + TerminalMonitor.rpcFields(value["params"] as? [String:Any] ?? [:]))
            }
            guard let params = (value["params"] ?? [:]) as? [String:Any] else {
                if let id = value["id"] {reject(id,L10n.text(.conversation,"codex.receive.text"))} else {fail(CodexProtocol.Failure.malformed(L10n.text(.conversation,"codex.receive.text.2")))}
                return
            }
            do {try CodexProtocol.validate(method,params)}
            catch {
                if let id = value["id"] {reject(id,error.localizedDescription)} else {fail(error)}
                return
            }
            if method == "thread/closed",let thread = params["threadId"] as? String {loadedThreads.removeValue(forKey:thread)}
            if let id = value["id"] { request(id,method,params) }
            else {TerminalMonitor.active?.serverEvent(method,params,connection:generation); event(method,params)}
        } else if let id = value["id"] as? Int {
            guard let call = pending.removeValue(forKey:id) else {
                TerminalMonitor.active?.write(.server,L10n.format(.tasks,"codex.call.text.4",String(describing:id)),.warning)
                return
            }
            func receipt(_ detail:String,_ level:TerminalMonitor.Level) {
                TerminalMonitor.active?.write(.server,L10n.text(.tasks,"codex.receipt.text")+TerminalMonitor.rpcName(call.method)+"  ·  RPC#\(id)  ·  "+call.elapsed+detail,level)
            }
            if let error = value["error"] as? [String:Any] {
                if TerminalMonitor.active != nil {receipt(TerminalMonitor.rpcError(error),.error)}
                call.reply(.failure(PetFailure(message:CodexErrorMessage.encode(error))))
            } else if let result = value["result"] as? [String:Any] {
                if TerminalMonitor.active != nil {receipt(TerminalMonitor.rpcResult(call.method,result),.success)}
                call.reply(.success(result))
            } else {
                receipt(L10n.text(.conversation,"codex.receipt.text"),.error)
                call.reply(.failure(CodexProtocol.Failure.malformed(L10n.text(.conversation,"codex.receipt.text.2"))))
            }
        }
    }
    private func fail(_ error: Error,stage:String = L10n.text(.conversation,"codex.fail.text")) {
        TerminalMonitor.active?.write(.server,stage+L10n.format(.tasks,"codex.fail.text",String(describing:generation),String(describing:pending.count))+TerminalMonitor.errorCode(error),.error)
        let callbacks = waiting, calls = pending.values.map(\.reply)
        waiting.removeAll(); pending.removeAll(); close(); connectionError = error.localizedDescription
        callbacks.forEach{$0(error)}; calls.forEach{$0(.failure(error))}; disconnected(error)
    }
    func close() {
        if let process {TerminalMonitor.active?.write(.server,L10n.format(.tasks,"codex.process.text",String(describing:process.processIdentifier),String(describing:generation)))}
        closing = true; ready = false; loadedThreads.removeAll(); generation += 1; expiration?.invalidate()
        try? input?.close(); input = nil
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now()+2) { if process.isRunning { kill(process.processIdentifier,SIGKILL) } }
            // AppKit 即将退出时也必须等到自有服务结束，否则异步清理来不及执行。
            process.waitUntilExit()
        }
        process = nil; cliVersion = nil; pending.removeAll(); waiting.removeAll()
    }
}
