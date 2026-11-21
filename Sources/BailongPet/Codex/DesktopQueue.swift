import AppKit
import Darwin

// Queue 只接纳文本。轮次仍由已加载原会话的桌面端启动和控制。
enum DesktopQueue {
    enum Waiting:LocalizedError {
        case desktop, queue
        var errorDescription:String? {
            switch self {
            case .desktop:return "Codex 桌面端尚未运行。"
            case .queue:return "Codex 桌面端尚未打开消息队列。"
            }
        }
    }
    struct Destination {
        let app:NSRunningApplication
        let cli:URL
        let store:URL

        static func running() throws -> Self {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier:"com.openai.codex").filter {!$0.isTerminated}
            if apps.isEmpty {throw Waiting.desktop}
            guard apps.count == 1,let app = apps.first,let bundle = app.bundleURL else {
                throw PetFailure(message:"请在一个 Codex 桌面端中打开原会话。")
            }
            let root = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory()+"/.codex"
            return Self(app:app,cli:bundle.appendingPathComponent(CodexConnection.packagedCLI),
                        store:URL(fileURLWithPath:root,isDirectory:true).standardizedFileURL)
        }

        func requireAvailableQueue(for thread:UUID) throws {
            let queue = store.appendingPathComponent("queue_1.sqlite")
            guard try Self.processes(using:queue).contains(where:belongsToDesktop) else {
                throw Waiting.queue
            }
            // 队列由各客户端共享。仅目标线程的写锁文件涉及本次投递。
            let lock = store.appendingPathComponent("thread-writer-locks")
                .appendingPathComponent(thread.uuidString.lowercased()+".lock")
            guard try Self.processes(using:lock).allSatisfy(belongsToDesktop) else {
                throw PetFailure(message:"当前桌面端以外的进程正在使用这条会话的写入锁。")
            }
        }

        private static func processes(using file:URL) throws -> Set<pid_t> {
            let flags = UInt32(PROC_LISTPIDSPATH_EXCLUDE_EVTONLY)
            var pids = [pid_t](repeating:0,count:16)
            while true {
                let capacity = pids.count * MemoryLayout<pid_t>.stride
                let bytes = pids.withUnsafeMutableBytes { buffer in
                    proc_listpidspath(UInt32(PROC_UID_ONLY),getuid(),file.path,flags,buffer.baseAddress,Int32(buffer.count))
                }
                if bytes < 0 {
                    if errno == ENOENT {return []}
                    throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))
                }
                if Int(bytes) < capacity {return Set(pids.prefix(Int(bytes)/MemoryLayout<pid_t>.stride))}
                pids = [pid_t](repeating:0,count:pids.count*2)
            }
        }

        private func belongsToDesktop(_ process:pid_t) -> Bool {
            guard !app.isTerminated else {return false}
            if process == app.processIdentifier {return true}
            guard let bundle = app.bundleURL else {return false}
            let prefix = bundle.resolvingSymlinksInPath().path+"/"
            var pid = process
            while pid > 1 && pid != app.processIdentifier {
                // 终端、编辑器和桌宠也能启动随附 CLI。父进程链须一直位于当前桌面应用包内。
                var path = [CChar](repeating:0,count:4 * Int(MAXPATHLEN))
                let length = path.withUnsafeMutableBytes {proc_pidpath(pid,$0.baseAddress,UInt32($0.count))}
                guard length > 0,String(cString:path).hasPrefix(prefix) else {return false}
                var info = proc_bsdshortinfo()
                let size = Int32(MemoryLayout.size(ofValue:info))
                guard proc_pidinfo(pid,PROC_PIDT_SHORTBSDINFO,0,&info,size) == size else {return false}
                pid = pid_t(info.pbsi_ppid)
            }
            return pid == app.processIdentifier
        }
    }

    static func prepare(thread:String,previousTurn:String,id:UUID,destination:@escaping () throws -> Destination,
                        waitForLaunch:Bool,isCurrent:@escaping () -> Bool,completion:@escaping (Result<Destination,Error>) -> Void) {
        func probe(_ pinned:Destination?) {
            guard isCurrent() else {return}
            let candidate = Result {try pinned ?? destination()}
            DispatchQueue.global(qos:.userInitiated).async {
                let ready = candidate.flatMap { target in
                    Result {
                        guard !target.app.isTerminated else {throw PetFailure(message:"Codex 桌面端已退出。")}
                        try target.requireAvailableQueue(for:id)
                        try DesktopHistoryReader.requireReplyConversation(thread,previousTurn:previousTurn,steering:false)
                        return target
                    }
                }
                DispatchQueue.main.async {
                    guard isCurrent() else {return}
                    if waitForLaunch,case .failure(let error) = ready,error is Waiting {
                        DispatchQueue.main.asyncAfter(deadline:.now()+1) {probe(try? candidate.get())}
                    } else {completion(ready)}
                }
            }
        }
        probe(nil)
    }

    static func receipt(_ data:Data,thread:UUID) -> UUID? {
        let fields = String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines).components(separatedBy:" ")
        guard fields.count == 6,fields[0] == "Queued",fields[1] == "message",fields[3] == "for",fields[4] == "thread",
              fields[5].last == ".",UUID(uuidString:String(fields[5].dropLast())) == thread else {return nil}
        return UUID(uuidString:fields[2])
    }

    // 后台持续排空输出。只解析回执和错误行，退出或超时只结束此次命令。
    static func submit(cli:URL,store:URL,thread:UUID,text:String,completion:@escaping (Result<UUID,Error>) -> Void) throws -> Process {
        let task = Process(), output = Pipe()
        task.executableURL = cli
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let directory = String(decoding:try encoder.encode(store.path),as:UTF8.self)
        task.arguments = ["queue","--disable","daemon_auto_start","-c","sqlite_home="+directory,
                          "--thread",thread.uuidString.lowercased(),"--message="+text]
        task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        // 投递只使用已核对的本机存储，避免继承启动终端的远程路由。
        task.environment = ["HOME":NSHomeDirectory(),"PATH":"/usr/bin:/bin:/usr/sbin:/sbin",
                            "CODEX_HOME":store.path,"TMPDIR":NSTemporaryDirectory()]

        task.standardInput = FileHandle.nullDevice
        task.standardError = output
        task.standardOutput = output
        try task.run()
        let timeout = DispatchWorkItem {
            if task.isRunning {kill(task.processIdentifier,SIGKILL)}
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+12,execute:timeout)
        DispatchQueue.global(qos:.userInitiated).async {
            var data = Data()
            while true {
                let chunk = output.fileHandleForReading.availableData
                if chunk.isEmpty {break}
                data.append(chunk.suffix(8192))
                if data.count > 8192 {data.removeFirst(data.count-8192)}
            }
            task.waitUntilExit()
            let lines = String(decoding:data,as:UTF8.self).split(whereSeparator:\.isNewline)
            let status = task.terminationStatus
            // CLI 向 stderr 输出警告，成功回执独占一行，须同时匹配队列项和原会话。
            let ids = lines.compactMap {receipt(Data($0.utf8),thread:thread)}
            let result:Result<UUID,Error>
            if status == 0,ids.count == 1 {
                result = .success(ids[0])
            } else {
                let reason:String
                if task.terminationReason == .uncaughtSignal {reason = "队列命令被信号 \(status) 结束。"}
                else if status == 0 {reason = "回执未匹配目标会话。"}
                else if let error = lines.last(where:{$0.hasPrefix("Error: ") || $0.hasPrefix("error: ")}) {
                    reason = String(error.prefix(320))
                } else {reason = "队列命令退出码为 \(status)。"}
                result = .failure(PetFailure(message:"入队结果待确认。"+reason))
            }
            DispatchQueue.main.async {timeout.cancel(); completion(result)}
        }
        return task
    }
}
