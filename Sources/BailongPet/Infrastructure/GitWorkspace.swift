import Foundation

enum GitTerminology:CaseIterable {
    case localized, english

    static let key = "gitTerminologyInEnglish"

    func text(_ key:String) -> String {
        L10n.text(self == .english ? .englishGit : .workspace,key)
    }

    func format(_ key:String,_ arguments:String...) -> String {
        String(format:text(key),arguments:arguments)
    }
}

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

        var title:String {title(using:.localized)}

        func title(using terms:GitTerminology) -> String {
            switch self {
            case .generic: return terms.text("gitStatusText.generic")
            case .github: return "GitHub"
            case .gitlab: return "GitLab"
            case .gitee: return "Gitee"
            case .gitea: return "Gitea"
            case .forgejo: return "Forgejo"
            case .huggingFace: return "Hugging Face"
            case .remote: return terms.text("gitStatusText.remote")
            }
        }
    }
    enum Group:CaseIterable {
        case conflicted, staged, unstaged, untracked
        var titleKey:String {
            switch self {
            case .conflicted:return "gitWorkspace.conflicted"
            case .staged:return "gitWorkspace.conflicted.2"
            case .unstaged:return "gitWorkspace.conflicted.3"
            case .untracked:return "gitWorkspace.conflicted.4"
            }
        }
    }
    enum Change:Equatable {
        case added, deleted, renamed, copied, typeChanged, modified, conflict(String)
        case submoduleCommit, submoduleDirty, submoduleCommitAndDirty, stagedGitlink
        func title(using terms:GitTerminology) -> String {
            switch self {
            case .added:return terms.text("gitWorkspace.change.text")
            case .deleted:return terms.text("gitWorkspace.change.text.2")
            case .renamed:return terms.text("gitWorkspace.change.text.3")
            case .copied:return terms.text("gitWorkspace.change.text.4")
            case .typeChanged:return terms.text("gitWorkspace.change.text.5")
            case .submoduleCommit:return terms.text("gitWorkspace.submodule.commit")
            case .submoduleDirty:return terms.text("gitWorkspace.submodule.dirty")
            case .submoduleCommitAndDirty:return terms.text("gitWorkspace.submodule.both")
            case .stagedGitlink:return terms.text("gitWorkspace.submodule.staged")
            case .modified:return terms.text("gitWorkspace.change.text.6")
            case .conflict(let code):
                switch code {
                case "DD":return terms.text("gitWorkspace.changes")
                case "AU":return terms.text("gitWorkspace.changes.2")
                case "UD":return terms.text("gitWorkspace.changes.3")
                case "UA":return terms.text("gitWorkspace.changes.4")
                case "DU":return terms.text("gitWorkspace.changes.5")
                case "AA":return terms.text("gitWorkspace.changes.6")
                case "UU":return terms.text("gitWorkspace.changes.7")
                default:return terms.text(Group.conflicted.titleKey)
                }
            }
        }
    }
    struct Entry:Equatable {let path:String, originalPath:String?, group:Group, change:Change}
    struct Stash:Equatable {let commit:String, subject:String, paths:[String]}
    struct Operation:Equatable {
        let compactTitle:String
        private let detailKey:String, progress:String?
        init(_ name:String, detailKey:String, progress:String? = nil) {
            compactTitle = progress.map {name+" "+$0} ?? name
            self.detailKey = detailKey
            self.progress = progress
        }
        func detailTitle(using terms:GitTerminology) -> String {
            if let progress {return terms.format(detailKey,progress)}
            return terms.text(detailKey)
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
    var remoteSpace:HuggingFaceSpace? {HuggingFaceSpace(host:remoteHost,repository:remoteRepository)}
    var pushSpace:HuggingFaceSpace? {
        pushTarget?.address.flatMap {HuggingFaceSpace(host:$0.host,repository:$0.repository)}
    }
    var repositoryKind:RepositoryKind {
        if let pushHost = pushTarget?.address?.host {return RepositoryKind(host:pushHost)}
        guard let remoteName,remoteName != "." else {return .generic}
        return RepositoryKind(host:remoteHost)
    }
    var counts:[Group:Int] {entries.reduce(into:[:]) {$0[$1.group,default:0] += 1}}
    var clean:Bool {entries.isEmpty}
    func detachedSummary(using terms:GitTerminology) -> String? {
        detached ? terms.text("gitWorkspace.text.2") : nil
    }
    var title:String {
        guard detached else {return branch}
        if let tag {return "#"+tag}
        return "@"+commit.prefix(8)
    }
    func summary(using terms:GitTerminology) -> String {
        let counts = counts
        var parts = Group.allCases.compactMap {group in
            counts[group].map {terms.text(group.titleKey)+terms.format("gitWorkspace.text.3",String($0))}
        }
        if parts.isEmpty {parts.append(terms.text("gitStatusText.clean"))}
        if stashes > 0 {parts.append(terms.format("gitWorkspace.text",terms.text("gitWorkspace.stashLabel"),String(stashes)))}
        return parts.joined(separator:" · ")
    }
    static func parse(_ data:Data) throws -> Self {
        var result = Self(), fields = data.split(separator:0,omittingEmptySubsequences:true).makeIterator()
        func change(_ code:Character) -> Change {
            switch code {case "A":return .added; case "D":return .deleted; case "R":return .renamed; case "C":return .copied; case "T":return .typeChanged; default:return .modified}
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
                    guard pair.count == 2,let ahead = Int(pair[0]),let behind = Int(pair[1]) else {throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.change.error"))}
                    result.ahead = ahead; result.behind = abs(behind)
                case "stash":result.stashes = Int(value) ?? 0
                default:break
                }
                continue
            }
            if record.hasPrefix("? ") {result.entries.append(Entry(path:String(record.dropFirst(2)),originalPath:nil,group:.untracked,change:.added)); continue}
            let kind = record.first, limit = kind == "1" ? 8 : kind == "2" ? 9 : kind == "u" ? 10 : 0
            guard limit > 0 else {throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.change.error.2"))}
            let parts = record.split(separator:" ",maxSplits:limit,omittingEmptySubsequences:false)
            guard parts.count == limit+1,parts[1].count == 2 else {throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.change.error.3"))}
            let path = String(parts[limit]), xy = Array(parts[1])
            var original:String?
            if kind == "2" {
                guard let old = fields.next() else {throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.change.error.4"))}
                original = String(decoding:old,as:UTF8.self)
            }
            if kind == "u" {
                result.entries.append(Entry(path:path,originalPath:original,group:.conflicted,change:.conflict(String(parts[1])))); continue
            }
            let sub = parts[2]
            if xy[0] != "." {
                let staged:Change = xy[0] == "M" && parts[3] == "160000" && parts[4] == "160000" ? .stagedGitlink : change(xy[0])
                result.entries.append(Entry(path:path,originalPath:original,group:.staged,change:staged))
            }
            // S<c><m><u> 比较子模块 HEAD 与父仓索引，并分别报告跟踪与未跟踪内容。
            let commitChanged = sub.hasPrefix("SC")
            let dirty = sub.hasPrefix("S") && (sub.hasSuffix("U") || sub.dropLast().hasSuffix("M"))
            if commitChanged || dirty {
                let state:Change = commitChanged ? (dirty ? .submoduleCommitAndDirty : .submoduleCommit) : .submoduleDirty
                result.entries.append(Entry(path:path,originalPath:original,group:.unstaged,change:state))
            } else if xy[1] != "." {
                result.entries.append(Entry(path:path,originalPath:original,group:.unstaged,change:change(xy[1])))
            }
        }
        guard !result.branch.isEmpty else {throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.change.error.5"))}
        return result
    }
}

enum GitRepositoryState:Equatable {
    case ready(GitWorkspaceStatus)
    case failed(root:String,message:String)

    var root:String {
        switch self {
        case .ready(let status):return status.root
        case .failed(let root,_):return root
        }
    }
    var status:GitWorkspaceStatus? {if case .ready(let status) = self {return status}; return nil}
    var failure:String? {if case .failed(_,let message) = self {return message}; return nil}
    var name:String {(root as NSString).lastPathComponent}
    func summary(using terms:GitTerminology) -> String {
        switch self {
        case .ready(let status):return [name,status.title,status.summary(using:terms)].joined(separator:" · ")
        case .failed:return name+" · "+L10n.text(.workspace,"status.presentStatus.title")
        }
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
    private func run(_ directory:String,_ arguments:[String],optional:Bool = false,outputLimit:Int = 8 * 1024 * 1024,
                     limitMessage:String = "gitWorkspace.run.error.2",timeoutMessage:String = "gitWorkspace.run.error") throws -> (Int32,Data) {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath:"/usr/bin/git")
        task.arguments = ["--no-optional-locks","-C",directory]+arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"; environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_NO_LAZY_FETCH"] = "1"
        // 会话 cwd 是唯一目标，不继承启动桌宠的终端中指向其他仓库的 Git 环境。
        for key in ["GIT_DIR","GIT_WORK_TREE","GIT_INDEX_FILE","GIT_COMMON_DIR"] {environment.removeValue(forKey:key)}
        task.environment = environment; task.standardOutput = pipe; task.standardError = pipe
        task.standardInput = FileHandle.nullDevice
        lock.lock()
        if cancelled {lock.unlock(); throw CancellationError()}
        timedOut = false
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
            if data.count+chunk.count <= outputLimit {if !exceeded {data.append(chunk)}}
            else {exceeded = true; if task.isRunning {task.terminate()}}
        }
        task.waitUntilExit()
        lock.lock(); let wasCancelled = cancelled, wasTimedOut = timedOut; lock.unlock()
        if wasCancelled {throw CancellationError()}
        if wasTimedOut {throw GitWorkspaceFailure(L10n.text(.workspace,timeoutMessage))}
        if exceeded {throw GitWorkspaceFailure(L10n.text(.workspace,limitMessage))}
        if task.terminationStatus != 0 && !(optional && task.terminationStatus == 1) {
            let message = String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            throw GitWorkspaceFailure(message.isEmpty ? L10n.format(.workspace,"gitWorkspace.run.error.3",String(describing:task.terminationStatus)) : message)
        }
        return (task.terminationStatus,data)
    }
    func readDiff(root:String,entry:GitWorkspaceStatus.Entry) throws -> WorkspaceDiffPatch {
        let options = ["--patch","--no-color","--no-ext-diff","--no-textconv","--unified=12",
            "--src-prefix=a/","--dst-prefix=b/","--output-indicator-new=+","--output-indicator-old=-","--output-indicator-context= "]
        let arguments:[String]
        if entry.group == .untracked {
            arguments = ["diff","--no-index"]+options+["--","/dev/null","./"+entry.path]
        } else {
            var comparison = ["--no-relative","--submodule=short","--ignore-submodules=none"]
            if entry.group == .staged {comparison.append("--cached")}
            if entry.group == .conflicted {comparison.append("--ours")}
            var paths = [entry.path]
            if let previous = entry.originalPath,entry.change == .renamed || entry.change == .copied {
                comparison.append(entry.change == .renamed ? "--find-renames" : "--find-copies-harder")
                paths.insert(previous,at:0)
            }
            arguments = ["--literal-pathspecs","diff"]+options+comparison+["--"]+paths
        }
        let (_,data) = try run(root,arguments,optional:entry.group == .untracked,outputLimit:WorkspaceDiffPatch.byteLimit,
                               limitMessage:"workspaceDiff.tooLarge",timeoutMessage:"workspaceDiff.timeout")
        guard let output = String(data:data,encoding:.utf8) else {
            throw GitWorkspaceFailure(L10n.text(.workspace,"workspaceDiff.encoding"))
        }
        // 无索引比较用状态 1 表示存在差异，路径消失也会返回 1。
        // 合并冲突的提示以及 Git 的诊断前缀不属于可拷贝的补丁。
        if let header = output.range(of:"(?m)^diff --git ",options:.regularExpression) {
            return try WorkspaceDiffPatch(String(output[header.lowerBound...]))
        }
        if output.isEmpty || (entry.group == .conflicted && output.hasPrefix("* Unmerged path ")) {
            return try WorkspaceDiffPatch("")
        }
        throw GitWorkspaceFailure(output.trimmingCharacters(in:.whitespacesAndNewlines))
    }
    func startDiff(root:String,entry:GitWorkspaceStatus.Entry,completion:@escaping (Result<WorkspaceDiffPatch,Error>) -> Void) {
        DispatchQueue.global(qos:.utility).async { [self] in
            let result = Result {try readDiff(root:root,entry:entry)}
            DispatchQueue.main.async {completion(result)}
        }
    }
    private func gitString(_ directory:String,_ args:[String],optional:Bool = false) throws -> String? {
        let (code,data) = try run(directory,args,optional:optional)
        guard code == 0 else {return nil}
        var value = String(decoding:data,as:UTF8.self)
        if value.hasSuffix("\n") {value.removeLast()}
        return value
    }
    func readStashes(directory:String,previous:[GitWorkspaceStatus.Stash] = []) throws -> [GitWorkspaceStatus.Stash] {
        let fields = try run(directory,["stash","list","-z","--format=%H%x00%gs"]).1
            .split(separator:0,omittingEmptySubsequences:false).dropLast()
        guard fields.count.isMultiple(of:2) else {throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.stashListError"))}
        let cached = Dictionary(previous.map {($0.commit,$0.paths)},uniquingKeysWith:{first,_ in first})
        let options = ["--name-only","-z","--no-renames","--no-ext-diff","--no-textconv"]
        return try stride(from:fields.startIndex,to:fields.endIndex,by:2).map {index in
            let commit = String(decoding:fields[index],as:UTF8.self)
            let subject = String(decoding:fields[index+1],as:UTF8.self)
            if let paths = cached[commit] {return .init(commit:commit,subject:subject,paths:paths)}
            let worktree = try run(directory,["-c","stash.showOnlyUntracked=false","stash","show","--include-untracked"]+options+[commit,"--"]).1
            // 暂存后又把工作树改回 HEAD 时，文件仍保存在 stash 的索引快照里。
            let indexTree = try run(directory,["diff-tree","--no-commit-id","-r"]+options+[commit+"^1",commit+"^2","--"]).1
            let paths = Set((worktree.split(separator:0)+indexTree.split(separator:0)).map {String(decoding:$0,as:UTF8.self)})
            return .init(commit:commit,subject:subject,paths:paths.sorted())
        }
    }
    func read(directory:String) throws -> GitWorkspaceStatus? {
        // 明确区分普通目录和查询失败，错误不能显示成干净。
        var isDirectory:ObjCBool = false
        guard FileManager.default.fileExists(atPath:directory,isDirectory:&isDirectory),isDirectory.boolValue else {throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.read.error"))}
        var cursor = URL(fileURLWithPath:directory,isDirectory:true).standardizedFileURL.resolvingSymlinksInPath()
        var found = false
        while cursor.path != "/" {
            if FileManager.default.fileExists(atPath:cursor.appendingPathComponent(".git").path) {found = true; break}
            cursor.deleteLastPathComponent()
        }
        guard found else {return nil}
        return try readRepository(directory:directory)
    }

    func readRepositories(directory:String) throws -> [GitRepositoryState] {
        if let status = try read(directory:directory) {return [.ready(status)]}
        let workspace = URL(fileURLWithPath:directory,isDirectory:true).standardizedFileURL.resolvingSymlinksInPath()
        let children = try FileManager.default.contentsOfDirectory(at:workspace,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])
        let roots = Set(children.filter {FileManager.default.fileExists(atPath:$0.appendingPathComponent(".git").path)}
            .map {$0.resolvingSymlinksInPath().path})
        return try roots.sorted().map {root in
            do {return .ready(try readRepository(directory:root))}
            catch is CancellationError {throw CancellationError()}
            catch {return .failed(root:root,message:error.localizedDescription)}
        }
    }

    private func readRepository(directory:String) throws -> GitWorkspaceStatus {
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
            guard fields.count == 6 else {throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.fields.text"))}
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
                    throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspace.right.text"))
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
        if exists("rebase-apply/applying") {return .init("am",detailKey:"gitWorkspace.rebaseStep.text")}
        let progressPaths:(current:String,total:String)
        if exists("rebase-apply") {
            progressPaths = ("rebase-apply/next","rebase-apply/last")
        } else if exists("rebase-merge") {
            progressPaths = ("rebase-merge/msgnum","rebase-merge/end")
        } else {
            let markers:[(path:String, operation:GitWorkspaceStatus.Operation)] = [
                ("MERGE_HEAD", .init("merge",detailKey:"gitWorkspace.rebaseStep.text.2")),
                ("CHERRY_PICK_HEAD", .init("cherry",detailKey:"gitWorkspace.rebaseStep.text.4")),
                ("REVERT_HEAD", .init("revert",detailKey:"gitWorkspace.rebaseStep.text.6")),
                ("BISECT_LOG", .init("bisect",detailKey:"gitWorkspace.rebaseStep.text.7"))
            ]
            return markers.first {exists($0.path)}?.operation
        }
        if let current = try rebaseStep(progressPaths.current), let total = try rebaseStep(progressPaths.total),
           current > 0, current <= total {
            let progress = "\(current)/\(total)"
            return .init("rebase",detailKey:"gitWorkspace.rebaseStep.text.9",progress:progress)
        }
        return .init("rebase",detailKey:"gitWorkspace.rebaseStep.text.11")
    }
    func start(directory:String,completion:@escaping (Result<[GitRepositoryState],Error>) -> Void) {
        DispatchQueue.global(qos:.utility).async { [self] in
            let result = Result {try readRepositories(directory:directory)}
            DispatchQueue.main.async {completion(result)}
        }
    }
    func startStashes(directory:String,previous:[GitWorkspaceStatus.Stash],completion:@escaping (Result<[GitWorkspaceStatus.Stash],Error>) -> Void) {
        DispatchQueue.global(qos:.utility).async { [self] in
            let result = Result {try readStashes(directory:directory,previous:previous)}
            DispatchQueue.main.async {completion(result)}
        }
    }
}
