import AppKit

final class CodexConnection {
    typealias Reply = (Result<[String:Any],Error>) -> Void
    var event: (String,[String:Any]) -> Void = { _,_ in }
    var request: (Any,String,[String:Any]) -> Void = { _,_,_ in }
    var disconnected: (Error) -> Void = { _ in }
    private var process: Process?
    private var input: FileHandle?
    private var serial = 0
    private var pending = [Int:(Reply,Date)]()
    private var waiting = [(Error?) -> Void]()
    private var ready = false
    private var loadedThreads = Set<String>()
    private var closing = false
    private var generation = 0
    private var expiration: Timer?
    private let reader = DispatchQueue(label:"白龙娘 Codex 协议")
    private var connectionError: String?
    private(set) var executableURL: URL?
    var isConnected:Bool {ready}
    var diagnostics: String {
        let state = ready ? "协议已连接" : process?.isRunning == true ? "正在初始化" : (connectionError.map { "连接失败：" + $0 } ?? "未连接")
        let pid = process.map { $0.isRunning ? String($0.processIdentifier) : "未运行" } ?? "未运行"
        return "\(state) · 进程 \(executableURL?.lastPathComponent ?? "codex") · PID \(pid) · 待回复 \(pending.count)\n可执行文件：\(executableURL?.path ?? "尚未启动")"
    }
    static func desktopApplications() -> [URL] {
        let running = NSWorkspace.shared.runningApplications.compactMap { app -> URL? in
            guard ["Codex","ChatGPT"].contains(app.localizedName ?? "") else { return nil }
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
            let lookup = Result {try DesktopHistoryReader.readTitles([id])}
            DispatchQueue.main.async {
                switch lookup {
                case .success(let titles) where titles[id] != nil:
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
                        } catch { DispatchQueue.main.async { if self?.generation == token { self?.fail(error) } }; return }
                    }
                }
                // 先交付最后一条完成/错误消息，再处理 EOF，避免退出回调抢先丢失结果。
                DispatchQueue.main.async {
                    guard let self, self.generation == token, !self.closing else {return}
                    self.fail(PetFailure(message:"Codex 连接已结束，任务状态未确认。"))
                }
            }
            expiration?.invalidate()
            expiration = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
                guard let self else{return}
                let expired = self.pending.filter { $0.value.1 < Date() }
                for (id,entry) in expired { self.pending.removeValue(forKey:id); entry.0(.failure(CodexProtocol.Failure.timeout)) }
            }
            call("initialize",["clientInfo":["name":"bailong_appkit","title":PetPreferences.shared.appName,"version":Paths.version],"capabilities":["experimentalApi":true]]) { [weak self] result in
                guard let self else{return}
                switch result {
                case .success:
                    guard self.send(["method":"initialized"]) else {return}; self.ready = true
                    let callbacks = self.waiting; self.waiting.removeAll(); callbacks.forEach{$0(nil)}
                case .failure(let error): self.fail(error)
                }
            }
        } catch { fail(error) }
    }
    // 同一服务进程内复用已加载的会话；恢复只用于本次连接尚未加载的历史会话。
    func prepareThread(_ id:String?,params:[String:Any],completion:@escaping (Result<String,Error>) -> Void) {
        if let id,loadedThreads.contains(id) {completion(.success(id)); return}
        var params = params
        if let id {params["threadId"] = id}
        call(id == nil ? "thread/start" : "thread/resume",params) { [weak self] result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let value):
                guard let thread = (value["thread"] as? [String:Any])?["id"] as? String,!thread.isEmpty else {
                    completion(.failure(CodexProtocol.Failure.malformed("缺少会话 ID"))); return
                }
                self?.loadedThreads.insert(thread)
                completion(.success(thread))
            }
        }
    }
    func call(_ method: String, _ params: [String:Any], completion: @escaping Reply) {
        guard input != nil else {completion(.failure(CodexProtocol.Failure.disconnected)); return}
        serial += 1; pending[serial] = (completion,Date().addingTimeInterval(30))
        send(["id":serial,"method":method,"params":params])
    }
    func reply(_ id: Any, _ result: [String:Any]) { send(["id":id,"result":result]) }
    func unsupported(_ id: Any, _ method: String) { send(["id":id,"error":["code":-32601,"message":"此客户端未支持 \(method)"]]) }
    @discardableResult private func send(_ value:[String:Any]) -> Bool {
        do {
            guard let input else {throw CodexProtocol.Failure.disconnected}
            var bytes = try JSONSerialization.data(withJSONObject:value); bytes.append(10)
            try input.write(contentsOf:bytes); return true
        } catch {fail(error); return false}
    }
    func abortUnconfirmedTask() {
        fail(PetFailure(message:"已关闭桌宠任务连接并回收服务进程；任务最终结果未确认，请在 Codex 核对。"))
    }
    func reject(_ id:Any,_ message:String) {send(["id":id,"error":["code":-32602,"message":message]])}
    private func receive(_ value: [String:Any]) {
        if let method = value["method"] as? String {
            guard let params = (value["params"] ?? [:]) as? [String:Any] else {
                if let id = value["id"] {reject(id,"请求缺少参数对象。")} else {fail(CodexProtocol.Failure.malformed("事件缺少参数对象"))}
                return
            }
            do {try CodexProtocol.validate(method,params)}
            catch {
                if let id = value["id"] {reject(id,error.localizedDescription)} else {fail(error)}
                return
            }
            if method == "thread/closed",let thread = params["threadId"] as? String {loadedThreads.remove(thread)}
            if let id = value["id"] { request(id,method,params) } else { event(method,params) }
        } else if let id = value["id"] as? Int, let (callback,_) = pending.removeValue(forKey:id) {
            if let error = value["error"] as? [String:Any] { callback(.failure(PetFailure(message:error["message"] as? String ?? "Codex 请求失败"))) }
            else if let result = value["result"] as? [String:Any] {callback(.success(result))}
            else {callback(.failure(CodexProtocol.Failure.malformed("回复缺少结果对象")))}
        }
    }
    private func fail(_ error: Error) {
        let callbacks = waiting, calls = pending.values.map{$0.0}
        waiting.removeAll(); pending.removeAll(); close(); connectionError = error.localizedDescription
        callbacks.forEach{$0(error)}; calls.forEach{$0(.failure(error))}; disconnected(error)
    }
    func close() {
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
