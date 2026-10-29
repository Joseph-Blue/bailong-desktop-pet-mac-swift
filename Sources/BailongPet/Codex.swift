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
    private var closing = false
    private var generation = 0
    private var expiration: Timer?
    private let reader = DispatchQueue(label:"白龙娘 Codex 协议")
    private(set) var executableURL: URL?
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
    func connect(_ callback: @escaping (Error?) -> Void) {
        if ready { callback(nil); return }
        waiting.append(callback)
        if process?.isRunning == true { return }
        do {
            closing = false; generation += 1; let token = generation
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
                            let message = try JSONSerialization.jsonObject(with:line) as! [String:Any]
                            DispatchQueue.main.async { if self?.generation == token { self?.receive(message) } }
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
                for (id,entry) in expired { self.pending.removeValue(forKey:id); entry.0(.failure(PetFailure(message:"Codex 请求超时，任务状态尚未确认。"))) }
            }
            call("initialize",["clientInfo":["name":"bailong_appkit","title":PetPreferences.shared.appName,"version":Paths.version],"capabilities":["experimentalApi":true]]) { [weak self] result in
                guard let self else{return}
                switch result {
                case .success:
                    self.send(["method":"initialized"]); self.ready = true
                    let callbacks = self.waiting; self.waiting.removeAll(); callbacks.forEach{$0(nil)}
                case .failure(let error): self.fail(error)
                }
            }
        } catch { fail(error) }
    }
    func call(_ method: String, _ params: [String:Any], completion: @escaping Reply) {
        serial += 1; pending[serial] = (completion,Date().addingTimeInterval(30))
        send(["id":serial,"method":method,"params":params])
    }
    func reply(_ id: Any, _ result: [String:Any]) { send(["id":id,"result":result]) }
    func unsupported(_ id: Any, _ method: String) { send(["id":id,"error":["code":-32601,"message":"此客户端未支持 \(method)"]]) }
    private func send(_ value: [String:Any]) {
        do { var bytes = try JSONSerialization.data(withJSONObject:value); bytes.append(10); try input?.write(contentsOf:bytes) }
        catch { fail(error) }
    }
    private func receive(_ value: [String:Any]) {
        if let method = value["method"] as? String {
            let params = value["params"] as? [String:Any] ?? [:]
            if let id = value["id"] { request(id,method,params) } else { event(method,params) }
        } else if let id = value["id"] as? Int, let (callback,_) = pending.removeValue(forKey:id) {
            if let error = value["error"] as? [String:Any] { callback(.failure(PetFailure(message:error["message"] as? String ?? "Codex 请求失败"))) }
            else { callback(.success(value["result"] as? [String:Any] ?? [:])) }
        }
    }
    private func fail(_ error: Error) {
        let callbacks = waiting, calls = pending.values.map{$0.0}
        waiting.removeAll(); pending.removeAll(); close()
        callbacks.forEach{$0(error)}; calls.forEach{$0(.failure(error))}; disconnected(error)
    }
    func close() {
        closing = true; ready = false; generation += 1; expiration?.invalidate()
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
