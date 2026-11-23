import Foundation

struct GitWorkspaceStatus:Equatable {
    enum RepositoryKind {
        case generic, github, gitlab, gitee, gitea, forgejo, huggingFace, remote

        static let additionalRemotes:[Self] = [.gitlab,.gitee,.gitea,.forgejo,.huggingFace]

        init(host:String?) {
            switch host?.lowercased() {
            case "github.com": self = .github
            case "gitlab.com", "altssh.gitlab.com": self = .gitlab
            case "gitee.com": self = .gitee
            case "gitea.com", "demo.gitea.com", "try.gitea.io": self = .gitea
            case "codeberg.org", "code.forgejo.org", "next.forgejo.org": self = .forgejo
            case "huggingface.co", "hf.co": self = .huggingFace
            default: self = .remote
            }
        }

        var title:String {
            switch self {
            case .generic: return "通用 Git 仓库"
            case .github: return "GitHub"
            case .gitlab: return "GitLab"
            case .gitee: return "Gitee"
            case .gitea: return "Gitea"
            case .forgejo: return "Forgejo"
            case .huggingFace: return "Hugging Face"
            case .remote: return "其他远端仓库"
            }
        }
    }
    enum Group:String,CaseIterable {case conflicted = "冲突", staged = "已暂存", unstaged = "未暂存", untracked = "未跟踪"}
    struct Entry:Equatable {let path:String, originalPath:String?, group:Group, change:String}
    struct Operation:Equatable {
        let compactTitle:String, detailTitle:String
        init(_ compactTitle:String, detailTitle:String? = nil) {
            self.compactTitle = compactTitle
            self.detailTitle = detailTitle ?? compactTitle
        }
    }
    var root = "", branch = "", commit = "", tag:String?, upstream:String?
    var ahead:Int?, behind:Int?, stashes = 0
    var initial = false, detached = false, operation:Operation?
    var remoteNames = [String]()
    var remoteName:String?, remoteHost:String?, remoteRepository:String?
    var remoteWebURL:URL?
    var entries = [Entry]()
    var observationPaths = [String]()
    var repositoryKind:RepositoryKind {
        guard let remoteName,remoteName != "." else {return .generic}
        return RepositoryKind(host:remoteHost)
    }
    var counts:[Group:Int] {entries.reduce(into:[:]) {$0[$1.group,default:0] += 1}}
    var clean:Bool {entries.isEmpty}
    static let stashLabel = "贮藏 (Stash)"
    var stashSummary:String? {stashes > 0 ? "\(Self.stashLabel) \(stashes) 条" : nil}
    var detachedSummary:String? {detached ? "当前不在任何分支上 (Detached HEAD)" : nil}
    var title:String {
        guard detached else {return branch}
        if let tag {return "#"+tag}
        return "@"+commit.prefix(8)
    }
    var summary:String {
        let counts = counts
        var parts = Group.allCases.compactMap {group in counts[group].map {group.rawValue+" \($0) 项"}}
        if parts.isEmpty {parts.append("工作区干净")}
        if let stashSummary {parts.append(stashSummary)}
        return parts.joined(separator:" · ")
    }
    static func parse(_ data:Data) throws -> Self {
        var result = Self(), fields = data.split(separator:0,omittingEmptySubsequences:true).makeIterator()
        func change(_ code:Character) -> String {
            switch code {case "A":return "新增"; case "D":return "删除"; case "R":return "重命名"; case "C":return "复制"; case "T":return "类型变化"; default:return "修改"}
        }
        while let field = fields.next() {
            let record = String(decoding:field,as:UTF8.self)
            if record.hasPrefix("# ") {
                let header = record.dropFirst(2).split(separator:" ",maxSplits:1,omittingEmptySubsequences:false)
                guard header.count == 2 else {continue}
                let value = String(header[1])
                switch header[0] {
                case "branch.head":result.detached = value == "(detached)"; result.branch = value
                case "branch.oid":result.initial = value == "(initial)"; result.commit = value
                case "branch.upstream":result.upstream = value
                case "branch.ab":
                    let pair = value.split(separator:" ")
                    guard pair.count == 2,let ahead = Int(pair[0]),let behind = Int(pair[1]) else {throw GitWorkspaceFailure("Git 分支计数格式无效。")}
                    result.ahead = ahead; result.behind = abs(behind)
                case "stash":result.stashes = Int(value) ?? 0
                default:break
                }
                continue
            }
            if record.hasPrefix("? ") {result.entries.append(Entry(path:String(record.dropFirst(2)),originalPath:nil,group:.untracked,change:"新增")); continue}
            let kind = record.first, limit = kind == "1" ? 8 : kind == "2" ? 9 : kind == "u" ? 10 : 0
            guard limit > 0 else {throw GitWorkspaceFailure("Git 文件状态格式无效。")}
            let parts = record.split(separator:" ",maxSplits:limit,omittingEmptySubsequences:false)
            guard parts.count == limit+1,parts[1].count == 2 else {throw GitWorkspaceFailure("Git 文件状态不完整。")}
            let path = String(parts[limit]), xy = Array(parts[1])
            var original:String?
            if kind == "2" {
                guard let old = fields.next() else {throw GitWorkspaceFailure("Git 重命名记录缺少原路径。")}
                original = String(decoding:old,as:UTF8.self)
            }
            if kind == "u" {
                let changes = ["DD":"双方删除","AU":"本地新增","UD":"本地修改／对方删除","UA":"对方新增","DU":"本地删除／对方修改","AA":"双方新增","UU":"双方修改"]
                result.entries.append(Entry(path:path,originalPath:original,group:.conflicted,change:changes[String(parts[1])] ?? "冲突")); continue
            }
            if xy[0] != "." {result.entries.append(Entry(path:path,originalPath:original,group:.staged,change:change(xy[0])))}
            if xy[1] != "." {result.entries.append(Entry(path:path,originalPath:original,group:.unstaged,change:change(xy[1])))}
            // 子模块自身的修改／未跟踪内容也属于当前工作树的变化。
            if xy[1] == ".",parts[2].hasPrefix("S"),parts[2].dropFirst().contains(where:{$0 != "."}) {
                result.entries.append(Entry(path:path,originalPath:nil,group:.unstaged,change:"子模块变化"))
            }
        }
        guard !result.branch.isEmpty else {throw GitWorkspaceFailure("Git 未返回当前分支。")}
        return result
    }
}

struct GitWorkspaceFailure:LocalizedError {
    let message:String
    init(_ message:String) {self.message = message}
    var errorDescription:String? {message}
}

// 只读查询由目录监听器调度。最后一个可见入口退出时取消。
final class GitWorkspaceRequest {
    private let lock = NSLock()
    private var process:Process?
    private var cancelled = false, timedOut = false
    func cancel() {lock.lock(); cancelled = true; if let process,process.isRunning {process.terminate()}; lock.unlock()}
    private func run(_ directory:String,_ arguments:[String],optional:Bool = false) throws -> (Int32,Data) {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath:"/usr/bin/git")
        task.arguments = ["--no-optional-locks","-C",directory]+arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"; environment["GIT_TERMINAL_PROMPT"] = "0"
        // 会话 cwd 是唯一目标，不继承启动桌宠的终端中指向其他仓库的 Git 环境。
        for key in ["GIT_DIR","GIT_WORK_TREE","GIT_INDEX_FILE","GIT_COMMON_DIR"] {environment.removeValue(forKey:key)}
        task.environment = environment; task.standardOutput = pipe; task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        lock.lock()
        if cancelled {lock.unlock(); throw CancellationError()}
        do {try task.run(); process = task} catch {lock.unlock(); throw error}
        lock.unlock()
        let timeout = DispatchWorkItem { [weak self,weak task] in
            guard let self,let task else {return}
            self.lock.lock()
            if self.process === task,task.isRunning {self.timedOut = true; task.terminate()}
            self.lock.unlock()
        }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+8,execute:timeout)
        defer {
            timeout.cancel()
            if task.isRunning {task.terminate()}
            task.waitUntilExit()
            lock.lock(); if process === task {process = nil}; lock.unlock()
        }
        var data = Data(), exceeded = false
        while let chunk = try pipe.fileHandleForReading.read(upToCount:65536),!chunk.isEmpty {
            if data.count+chunk.count <= 8*1024*1024 {if !exceeded {data.append(chunk)}}
            else {exceeded = true; if task.isRunning {task.terminate()}}
        }
        task.waitUntilExit()
        lock.lock(); let wasCancelled = cancelled, wasTimedOut = timedOut; lock.unlock()
        if wasCancelled {throw CancellationError()}
        if wasTimedOut {throw GitWorkspaceFailure("Git 状态查询超时，点击重试。")}
        if exceeded {throw GitWorkspaceFailure("Git 状态超过 8 MiB，无法显示完整文件列表。")}
        if task.terminationStatus != 0 && !(optional && task.terminationStatus == 1) {
            let message = String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            throw GitWorkspaceFailure(message.isEmpty ? "Git 查询失败（\(task.terminationStatus)）。" : message)
        }
        return (task.terminationStatus,data)
    }
    func read(directory:String) throws -> GitWorkspaceStatus? {
        // 明确区分普通目录和查询失败，错误不能显示成干净。
        var isDirectory:ObjCBool = false
        guard FileManager.default.fileExists(atPath:directory,isDirectory:&isDirectory),isDirectory.boolValue else {throw GitWorkspaceFailure("工作区目录不存在或无法访问。")}
        var cursor = URL(fileURLWithPath:directory,isDirectory:true).standardizedFileURL.resolvingSymlinksInPath()
        var found = false
        while cursor.path != "/" {
            if FileManager.default.fileExists(atPath:cursor.appendingPathComponent(".git").path) {found = true; break}
            cursor.deleteLastPathComponent()
        }
        guard found else {return nil}
        func string(_ args:[String],optional:Bool = false) throws -> String? {
            let (code,data) = try run(directory,args,optional:optional)
            guard code == 0 else {return nil}
            var value = String(decoding:data,as:UTF8.self)
            if value.hasSuffix("\n") {value.removeLast()}
            return value
        }
        let root = try string(["rev-parse","--show-toplevel"])!
        var result = try GitWorkspaceStatus.parse(run(directory,["status","--porcelain=v2","-z","--branch","--ahead-behind","--show-stash","--untracked-files=all","--ignore-submodules=none"]).1)
        result.root = root
        let gitDirectory = try string(["rev-parse","--absolute-git-dir"])!
        let commonDirectory = try string(["rev-parse","--path-format=absolute","--git-common-dir"])!
        result.observationPaths = Array(Set([root,gitDirectory,commonDirectory])).sorted()
        result.operation = try repositoryOperation(in:URL(fileURLWithPath:gitDirectory))
        if result.detached,
           let tag = try string(["for-each-ref","--points-at=\(result.commit)","--sort=refname","--count=1","--format=%(refname:strip=2)","refs/tags"]),
           !tag.isEmpty {
            result.tag = tag
        }
        if result.upstream != nil,!result.detached {
            result.remoteName = try string(["config","--get","branch.\(result.branch).remote"],optional:true)
        }
        result.remoteNames = try string(["remote"])!.split(separator:"\n").map(String.init)
        if result.remoteName == nil,result.remoteNames.count == 1 {result.remoteName = result.remoteNames[0]}
        if let remote = result.remoteName,remote != ".",let address = try string(["remote","get-url",remote]) {
            // 仅投影主机与仓库路径，不把 remote URL 中的用户信息交给显示层。
            if let url = URLComponents(string:address),let host = url.host {
                result.remoteHost = host; result.remoteRepository = url.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
                if ["https","http"].contains(url.scheme?.lowercased() ?? "") {
                    var web = url; web.user = nil; web.password = nil; web.query = nil; web.fragment = nil
                    result.remoteWebURL = web.url
                }
            } else if !address.hasPrefix("/"),let colon = address.firstIndex(of:":") {
                result.remoteHost = String(address[..<colon].split(separator:"@").last ?? "")
                result.remoteRepository = String(address[address.index(after:colon)...])
            } else {result.remoteRepository = address}
            if result.remoteWebURL == nil,let host = result.remoteHost,
               ["github.com","gitlab.com","gitee.com","bitbucket.org"].contains(host.lowercased()),let repository = result.remoteRepository {
                var web = URLComponents(); web.scheme = "https"; web.host = host
                web.path = "/"+(repository.hasSuffix(".git") ? String(repository.dropLast(4)) : repository)
                result.remoteWebURL = web.url
            }
        }
        return result
    }
    private func repositoryOperation(in gitDirectory:URL) throws -> GitWorkspaceStatus.Operation? {
        func exists(_ path:String) -> Bool {
            FileManager.default.fileExists(atPath:gitDirectory.appendingPathComponent(path).path)
        }
        func rebaseStep(_ path:String) throws -> Int? {
            do {
                let value = try String(contentsOf:gitDirectory.appendingPathComponent(path),encoding:.utf8)
                return Int(value.trimmingCharacters(in:.whitespacesAndNewlines))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                // 变基开始或结束时，步数文件可能尚未创建或已被移除。
                return nil
            }
        }
        if exists("rebase-apply/applying") {return .init("应用补丁中")}
        let progressPaths:(current:String,total:String)
        if exists("rebase-apply") {
            progressPaths = ("rebase-apply/next","rebase-apply/last")
        } else if exists("rebase-merge") {
            progressPaths = ("rebase-merge/msgnum","rebase-merge/end")
        } else {
            let markers:[(path:String, operation:GitWorkspaceStatus.Operation)] = [
                ("MERGE_HEAD", .init("合并中")),
                ("CHERRY_PICK_HEAD", .init("拣选中", detailTitle:"拣选提交 (Cherry-pick) 进行中")),
                ("REVERT_HEAD", .init("还原中", detailTitle:"撤销提交改动 (Revert) 进行中")),
                ("BISECT_LOG", .init("二分查找中"))
            ]
            return markers.first {exists($0.path)}?.operation
        }
        if let current = try rebaseStep(progressPaths.current), let total = try rebaseStep(progressPaths.total),
           current > 0, current <= total {
            let progress = "\(current)/\(total)"
            return .init("变基中 \(progress)", detailTitle:"变基 (Rebase) \(progress)")
        }
        return .init("变基中", detailTitle:"变基 (Rebase) 进行中")
    }
    func start(directory:String,completion:@escaping (Result<GitWorkspaceStatus?,Error>) -> Void) {
        DispatchQueue.global(qos:.utility).async { [self] in
            let result = Result {try read(directory:directory)}
            DispatchQueue.main.async {completion(result)}
        }
    }
}
