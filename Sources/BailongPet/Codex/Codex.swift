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
    private let reader = DispatchQueue(label:"白龙娘 Codex 协议")
    private var connectionError: String?
    private(set) var executableURL: URL?
    var isConnected:Bool {ready}
    var connectionGeneration:Int {generation}
    func reportMonitorState(to monitor:TerminalMonitor) {
        let state = ready ? "已就绪" : process == nil ? "未连接" : "握手中"
        let pid = process.map {"  ·  PID \($0.processIdentifier)"} ?? ""
        monitor.write(.server,"连接快照  ·  "+state+pid+"  ·  待回执 \(pending.count)  ·  已加载会话 \(loadedThreads.count)")
        for (id,call) in pending.sorted(by:{$0.key < $1.key}) {
            monitor.write(.server,"等待回执  "+TerminalMonitor.rpcName(call.method)+"  ·  RPC#\(id)  ·  已等待 "+call.elapsed)
        }
    }
    var diagnostics: String {
        let state = ready ? "协议已连接" : process?.isRunning == true ? "正在初始化" : (connectionError.map { "连接失败：" + $0 } ?? "未连接")
        let pid = process.map { $0.isRunning ? String($0.processIdentifier) : "未运行" } ?? "未运行"
        return "\(state) · 进程 \(executableURL?.lastPathComponent ?? "codex") · PID \(pid) · 待回复 \(pending.count)\n可执行文件：\(executableURL?.path ?? "尚未启动")"
    }
    private static func isDesktopApplication(_ app:NSRunningApplication) -> Bool {
        !app.isTerminated && (app.bundleIdentifier == "com.openai.codex" || ["Codex","ChatGPT"].contains(app.localizedName ?? ""))
    }
    static func desktopApplications() -> [URL] {
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> URL? in
            guard isDesktopApplication(app) else { return nil }
            return app.bundleURL
        }
        return running + ["/Applications/Codex.app",NSHomeDirectory()+"/Applications/Codex.app",
            "/Applications/ChatGPT.app",NSHomeDirectory()+"/Applications/ChatGPT.app"].map {URL(fileURLWithPath:$0)}
    }
    static func executable() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let explicit = env["BAILONG_CODEX_BIN"], !explicit.isEmpty {
            guard FileManager.default.isExecutableFile(atPath:explicit) else {throw PetFailure(message:"指定的 Codex 程序不可执行："+explicit)}
            return URL(fileURLWithPath:explicit)
        }
        // 优先当前桌面应用内置版本，防止旧 PATH CLI 不支持桌面端当前模型。
        let bundled = desktopApplications().flatMap { app in
            ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
             "Contents/Resources/codex", "Contents/Resources/codex-cli/codex"].map {app.appendingPathComponent($0).path}
        }
        let candidates = bundled + (env["PATH"] ?? "").split(separator:":").map {String($0)+"/codex"} +
            [NSHomeDirectory()+"/.local/bin/codex","/opt/homebrew/bin/codex","/usr/local/bin/codex"]
        guard let path = candidates.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else {
            throw PetFailure(message:"没有找到可用的 Codex。请安装或更新 Codex 桌面应用并登录，再重试。")
        }
        return URL(fileURLWithPath:path)
    }
    static func openDesktop() {
        guard let app = desktopApplications().first(where:{FileManager.default.fileExists(atPath:$0.path)}) else {return}
        NSWorkspace.shared.open(app)
    }
    private static let navigationQueue = DispatchQueue(label:"白龙娘 Codex 会话定位",qos:.userInitiated)
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
                    guard try lookup.get(),let url = threadURL(id) else {throw PetFailure(message:"原 Codex 会话已不存在。")}
                    guard let app = desktopApplications().first(where:{FileManager.default.fileExists(atPath:$0.path)}) else {
                        throw PetFailure(message:"未找到 Codex 桌面应用。")
                    }
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    let runningApp = NSWorkspace.shared.runningApplications.first { isDesktopApplication($0) && $0.bundleURL?.standardizedFileURL == app.standardizedFileURL }
                    let coldStart = runningApp == nil || (runningApp?.launchDate.map {Date().timeIntervalSince($0) < 10} == true)
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
            connectionError = nil; closing = false; generation += 1; let token = generation
            let task = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            task.executableURL = try Self.executable(); executableURL = task.executableURL; task.arguments = ["app-server","--listen","stdio://"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = [task.executableURL!.deletingLastPathComponent().path, NSHomeDirectory()+"/.local/bin","/opt/homebrew/bin","/usr/local/bin",env["PATH"] ?? ""].joined(separator:":")
            task.environment = env; task.standardInput = stdin; task.standardOutput = stdout; task.standardError = stderr
            // 消费 stderr 防止子进程阻塞；不保存原始诊断流或用户对话日志。
            stderr.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
            try task.run(); process = task; input = stdin.fileHandleForWriting
            TerminalMonitor.active?.write(.server,"启动子进程  ·  stdio  ·  PID \(task.processIdentifier)  ·  连接#\(token)")
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
                        } catch { DispatchQueue.main.async { if self?.generation == token { self?.fail(error,stage:"解析协议帧") } }; return }
                    }
                }
                // 先交付最后一条完成/错误消息，再处理 EOF，避免退出回调抢先丢失结果。
                DispatchQueue.main.async {
                    guard let self, self.generation == token, !self.closing else {return}
                    self.fail(PetFailure(message:"Codex 连接已结束，任务状态未确认。"),stage:"读取到 EOF")
                }
            }
            expiration?.invalidate()
            expiration = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
                guard let self else{return}
                let expired = self.pending.filter { $0.value.deadline < Date() }
                for (id,_) in expired {
                    guard let call = self.pending.removeValue(forKey:id) else {continue}
                    TerminalMonitor.active?.write(.server,"× 超时  "+TerminalMonitor.rpcName(call.method)+"  ·  RPC#\(id)  ·  "+call.elapsed,.error)
                    call.reply(.failure(CodexProtocol.Failure.timeout))
                }
            }
            call("initialize",["clientInfo":["name":"bailong_appkit","title":PetPreferences.shared.appName,"version":Paths.version],"capabilities":["experimentalApi":true]]) { [weak self] result in
                guard let self,self.generation == token else{return}
                switch result {
                case .success:
                    guard self.send(["method":"initialized"]) else {return}; self.ready = true
                    TerminalMonitor.active?.write(.server,"→ 通知  initialized  ·  握手完成  ·  连接#\(token)",.success)
                    let callbacks = self.waiting; self.waiting.removeAll(); callbacks.forEach{$0(nil)}
                case .failure(let error): self.fail(error,stage:"初始化握手")
                }
            }
        } catch { fail(error,stage:"启动子进程") }
    }
    // 同一服务进程内复用已加载的会话；恢复只用于本次连接尚未加载的历史会话。
    func prepareThread(_ id:String?,params:[String:Any],completion:@escaping (Result<PreparedThread,Error>) -> Void) {
        if let id,let prepared = loadedThreads[id] {
            TerminalMonitor.active?.write(.server,"复用已加载会话  ·  会话#"+TerminalMonitor.tag(id))
            completion(.success(prepared)); return
        }
        var params = params
        if let id {params["threadId"] = id}
        call(id == nil ? "thread/start" : "thread/resume",params) { [weak self] result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let value):
                guard let thread = value["thread"] as? [String:Any],let id = thread["id"] as? String,!id.isEmpty else {
                    completion(.failure(CodexProtocol.Failure.malformed("缺少会话 ID"))); return
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
            TerminalMonitor.active?.write(.server,"× 未发送  "+TerminalMonitor.rpcName(method)+"  ·  连接未建立",.warning)
            completion(.failure(CodexProtocol.Failure.disconnected)); return
        }
        serial += 1
        pending[serial] = PendingCall(reply:completion,method:method,deadline:Date().addingTimeInterval(30))
        if send(["id":serial,"method":method,"params":params]) {
            TerminalMonitor.active?.write(.server,"→ 请求  "+TerminalMonitor.rpcName(method)+"  ·  RPC#\(serial)"+TerminalMonitor.rpcFields(params))
        }
    }
    func reply(_ id: Any, _ result: [String:Any]) {
        if send(["id":id,"result":result]) {TerminalMonitor.active?.write(.server,"→ 应答  服务请求#"+TerminalMonitor.serverRequestID(id))}
    }
    func unsupported(_ id: Any, _ method: String) {
        if send(["id":id,"error":["code":-32601,"message":"此客户端未支持 \(method)"]]) {
            TerminalMonitor.active?.write(.server,"→ 应答  服务请求#"+TerminalMonitor.serverRequestID(id)+"  ·  方法不支持 (-32601)",.warning)
        }
    }
    @discardableResult private func send(_ value:[String:Any]) -> Bool {
        do {
            guard let input else {throw CodexProtocol.Failure.disconnected}
            var bytes = try JSONSerialization.data(withJSONObject:value); bytes.append(10)
            try input.write(contentsOf:bytes); return true
        } catch {fail(error,stage:"写入协议帧"); return false}
    }
    func abortUnconfirmedTask() {
        fail(PetFailure(message:"已关闭桌宠任务连接并回收服务进程；任务最终结果未确认，请在 Codex 核对。"))
    }
    func reject(_ id:Any,_ message:String) {
        if send(["id":id,"error":["code":-32602,"message":message]]) {
            TerminalMonitor.active?.write(.server,"→ 应答  服务请求#"+TerminalMonitor.serverRequestID(id)+"  ·  拒绝 (-32602)",.warning)
        }
    }
    private func receive(_ value: [String:Any]) {
        if let method = value["method"] as? String {
            if let id = value["id"] {
                TerminalMonitor.active?.write(.server,"← 请求  "+TerminalMonitor.rpcName(method)+"  ·  服务请求#"+TerminalMonitor.serverRequestID(id)
                    + TerminalMonitor.rpcFields(value["params"] as? [String:Any] ?? [:]))
            }
            guard let params = (value["params"] ?? [:]) as? [String:Any] else {
                if let id = value["id"] {reject(id,"请求缺少参数对象。")} else {fail(CodexProtocol.Failure.malformed("事件缺少参数对象"))}
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
                TerminalMonitor.active?.write(.server,"← 回执  RPC#\(id)  ·  无对应的待处理请求",.warning)
                return
            }
            func receipt(_ detail:String,_ level:TerminalMonitor.Level) {
                TerminalMonitor.active?.write(.server,"← 回执  "+TerminalMonitor.rpcName(call.method)+"  ·  RPC#\(id)  ·  "+call.elapsed+detail,level)
            }
            if let error = value["error"] as? [String:Any] {
                if TerminalMonitor.active != nil {receipt(TerminalMonitor.rpcError(error),.error)}
                call.reply(.failure(PetFailure(message:CodexErrorMessage.encode(error))))
            } else if let result = value["result"] as? [String:Any] {
                if TerminalMonitor.active != nil {receipt(TerminalMonitor.rpcResult(call.method,result),.success)}
                call.reply(.success(result))
            } else {
                receipt("  ·  缺少结果对象",.error)
                call.reply(.failure(CodexProtocol.Failure.malformed("回复缺少结果对象")))
            }
        }
    }
    private func fail(_ error: Error,stage:String = "连接中断") {
        TerminalMonitor.active?.write(.server,stage+"  ·  连接#\(generation)  ·  待回执 \(pending.count)  ·  "+TerminalMonitor.errorCode(error),.error)
        let callbacks = waiting, calls = pending.values.map(\.reply)
        waiting.removeAll(); pending.removeAll(); close(); connectionError = error.localizedDescription
        callbacks.forEach{$0(error)}; calls.forEach{$0(.failure(error))}; disconnected(error)
    }
    func close() {
        if let process {TerminalMonitor.active?.write(.server,"关闭连接  ·  PID \(process.processIdentifier)  ·  连接#\(generation)")}
        closing = true; ready = false; loadedThreads.removeAll(); generation += 1; expiration?.invalidate()
        try? input?.close(); input = nil
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now()+2) { if process.isRunning { kill(process.processIdentifier,SIGKILL) } }
            // AppKit 即将退出时也必须等到自有服务结束，否则异步清理来不及执行。
            process.waitUntilExit()
        }
        process = nil; pending.removeAll(); waiting.removeAll()
    }
}
