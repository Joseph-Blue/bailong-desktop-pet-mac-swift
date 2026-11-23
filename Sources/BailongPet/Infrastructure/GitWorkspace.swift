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
    struct RemoteAddress:Equatable {
        let host:String?, repository:String, webURL:URL?
        let repositoryIdentity:String

        init(_ address:String) {
            var web:URL?
            var port:Int?
            if var url = URLComponents(string:address),let host = url.host {
                self.host = host
                repository = url.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
                let scheme = url.scheme?.lowercased()
                let defaultPorts = ["http":80,"https":443,"ssh":22,"git":9418]
                if let portNumber = url.port,portNumber != defaultPorts[scheme ?? ""] {port = portNumber}
                if scheme == "https" || scheme == "http" {
                    url.user = nil; url.password = nil; url.query = nil; url.fragment = nil
                    web = url.url
                }
            } else if !address.hasPrefix("/"),let colon = address.firstIndex(of:":") {
                host = String(address[..<colon].split(separator:"@").last ?? "")
                repository = String(address[address.index(after:colon)...])
            } else {
                host = nil
                repository = address
            }
            let path = repository.hasSuffix(".git") ? String(repository.dropLast(4)) : repository
            if web == nil,let host,["github.com","gitlab.com","gitee.com","bitbucket.org"].contains(host.lowercased()) {
                var url = URLComponents(); url.scheme = "https"; url.host = host; url.path = "/"+path
                web = url.url
            }
            webURL = web
            if let host {
                let hostname = host.lowercased()
                let authority: String
                switch (hostname,port) {
                case ("hf.co",nil): authority = "huggingface.co"
                case ("altssh.gitlab.com",443), ("altssh.gitlab.com",nil): authority = "gitlab.com"
                default: authority = port.map {"\(hostname):\($0)"} ?? hostname
                }
                repositoryIdentity = authority+"/"+path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
            } else {repositoryIdentity = address}
        }
    }
    struct PushTarget:Equatable {
        let remote:String, branch:String, address:RemoteAddress?
        let ahead:Int?, behind:Int?
        var kind:RepositoryKind {RepositoryKind(host:address?.host)}
    }
    var root = "", branch = "", commit = "", tag:String?, upstream:String?
    var ahead:Int?, behind:Int?, stashes = 0
    var initial = false, detached = false, operation:Operation?
    var remoteNames = [String]()
    var remoteName:String?, remoteHost:String?, remoteRepository:String?
    var remoteWebURL:URL?
    var pushTarget:PushTarget?
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
        if arguments.first == "rev-list" {environment["GIT_NO_LAZY_FETCH"] = "1"}
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
    private func gitString(_ directory:String,_ args:[String],optional:Bool = false) throws -> String? {
        let (code,data) = try run(directory,args,optional:optional)
        guard code == 0 else {return nil}
        var value = String(decoding:data,as:UTF8.self)
        if value.hasSuffix("\n") {value.removeLast()}
        return value
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
            try gitString(directory,args,optional:optional)
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
        let branchRemote = result.detached ? nil : try string(["config","--get","branch.\(result.branch).remote"],optional:true)
        if result.upstream != nil {result.remoteName = branchRemote}
        result.remoteNames = try string(["remote"])!.split(separator:"\n").map(String.init)
        if result.remoteName == nil,result.remoteNames.count == 1 {result.remoteName = result.remoteNames[0]}
        let fetchAddress = try result.remoteName.flatMap {remote -> GitWorkspaceStatus.RemoteAddress? in
            guard remote != ".",let address = try string(["remote","get-url","--",remote]) else {return nil}
            return GitWorkspaceStatus.RemoteAddress(address)
        }
        result.remoteHost = fetchAddress?.host
        result.remoteRepository = fetchAddress?.repository
        result.remoteWebURL = fetchAddress?.webURL
        result.pushTarget = try pushTarget(in:directory,status:result,branchRemote:branchRemote,fetchAddress:fetchAddress)
        return result
    }

    private func pushTarget(in directory:String,status:GitWorkspaceStatus,branchRemote:String?,
                            fetchAddress:GitWorkspaceStatus.RemoteAddress?) throws -> GitWorkspaceStatus.PushTarget? {
        guard !status.detached,!status.initial,!status.remoteNames.isEmpty else {return nil}
        let localRef = "refs/heads/"+status.branch
        func references(simpleFork:Bool = false) throws -> (remote:String, destination:String, tracking:String, upstream:String, upstreamDestination:String)? {
            let options = simpleFork ? ["-c","push.default=current"] : []
            let format = "%(refname)%00%(push:remotename)%00%(push:remoteref)%00%(push)%00%(upstream)%00%(upstream:remoteref)"
            let output = try gitString(directory,options+["for-each-ref","--count=1","--format=\(format)","--",localRef])!
            guard !output.isEmpty else {return nil}
            let fields = output.split(separator:"\0",omittingEmptySubsequences:false).map(String.init)
            guard fields.count == 6 else {throw GitWorkspaceFailure("Git 推送引用格式无效。")}
            guard fields[0] == localRef else {return nil}
            return (fields[1],fields[2],fields[3],fields[4],fields[5])
        }
        guard var refs = try references() else {return nil}
        let defaultRemote = status.remoteNames.count == 1 ? status.remoteNames[0] : "origin"
        let remote = refs.remote.isEmpty ? defaultRemote : refs.remote
        guard status.remoteNames.contains(remote) else {return nil}
        if remote != (branchRemote ?? defaultRemote),refs.destination.isEmpty {
            let mode = try gitString(directory,["config","--get","push.default"],optional:true) ?? "simple"
            if mode == "upstream" {return nil}
            if mode == "simple",refs.tracking.isEmpty {
                // 推送到另一远端时，Git 的 simple 模式推送当前分支。@{push} 未必能解析这个分支。
                guard let forkRefs = try references(simpleFork:true) else {return nil}
                refs = forkRefs
            }
        }
        guard !refs.tracking.isEmpty || !refs.destination.isEmpty else {return nil}
        let destination = refs.destination.isEmpty
            ? (refs.tracking == refs.upstream && !refs.upstreamDestination.isEmpty ? refs.upstreamDestination : localRef)
            : refs.destination
        let branch = destination.hasPrefix("refs/heads/") ? String(destination.dropFirst("refs/heads/".count)) : destination
        let pushURLs = try gitString(directory,["remote","get-url","--push","--all","--",remote])!
        let addresses = pushURLs.split(separator:"\n").map {GitWorkspaceStatus.RemoteAddress(String($0))}
        let identities = Set(addresses.map(\.repositoryIdentity))
        if status.upstream != nil,destination == refs.upstreamDestination,
           let fetchAddress,identities == [fetchAddress.repositoryIdentity] {return nil}

        let address = identities.count == 1 ? addresses.first : nil
        // 推送 URL 与取回 URL 指向同一仓库时，本地跟踪引用才能用于比较。
        var ahead:Int?, behind:Int?
        if let address,!refs.tracking.isEmpty {
            let trackedAddress = remote == status.remoteName ? fetchAddress
                : try gitString(directory,["remote","get-url","--",remote]).map(GitWorkspaceStatus.RemoteAddress.init)
            if trackedAddress?.repositoryIdentity == address.repositoryIdentity,
               let trackedCommit = try gitString(directory,["rev-parse","--verify","--quiet",refs.tracking+"^{commit}"],optional:true) {
                let counts = try gitString(directory,["rev-list","--left-right","--count",status.commit+"..."+trackedCommit,"--"])!
                    .split(whereSeparator:\.isWhitespace)
                guard counts.count == 2,let left = Int(counts[0]),let right = Int(counts[1]) else {
                    throw GitWorkspaceFailure("Git 推送分支计数格式无效。")
                }
                ahead = left; behind = right
            }
        }
        return GitWorkspaceStatus.PushTarget(remote:remote,branch:branch,address:address,ahead:ahead,behind:behind)
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
