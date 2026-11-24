import Foundation

// 同一目录的可见信息栏共用一次只读查询和一份文件监听，最后一个入口退出时释放。
final class GitWorkspaceMonitor {
    private struct Listener {
        let gitChanged:(Bool,Bool) -> Void
        let spaceChanged:() -> Void
    }
    private static var directories = [String:GitWorkspaceMonitor]()
    static func directory(_ path:String) -> GitWorkspaceMonitor {
        if let monitor = directories[path] {return monitor}
        let monitor = GitWorkspaceMonitor(path:path); directories[path] = monitor
        return monitor
    }
    private let path:String, observation = GitWorkspaceObservation()
    private var listeners = [ObjectIdentifier:Listener]()
    private var pending:DispatchWorkItem?, request:GitWorkspaceRequest?
    private var refreshAgain = false
    private(set) var repositories = [GitRepositoryState]()
    private(set) var failure:String?, observationFailure:String?
    private(set) var hasBaseline = false
    private var spaceRefresh:DispatchWorkItem?
    private var spaceRequests = [HuggingFaceSpace:(token:UUID,task:URLSessionDataTask)]()
    private var spaces = Set<HuggingFaceSpace>()
    private(set) var spaceStatuses = [HuggingFaceSpace:HuggingFaceSpace.Result]()
    var loading:Bool {request != nil}
    private init(path:String) {
        self.path = path
        observation.onChange = { [weak self] in self?.scheduleRefresh() }
    }
    func attach(_ owner:AnyObject,spaceChanged:@escaping () -> Void = {},changed:@escaping (Bool,Bool) -> Void) {
        listeners[ObjectIdentifier(owner)] = Listener(gitChanged:changed,spaceChanged:spaceChanged)
        if listeners.count == 1 {refresh()}
    }
    func detach(_ owner:AnyObject) {
        listeners.removeValue(forKey:ObjectIdentifier(owner))
        if listeners.isEmpty {
            pending?.cancel(); request?.cancel(); request = nil; observation.stop()
            updateSpaces([])
            Self.directories.removeValue(forKey:path)
        }
    }
    func scheduleRefresh() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pending = work; DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:work)
    }
    func refresh() {
        guard !listeners.isEmpty else {return}
        pending?.cancel(); pending = nil
        guard request == nil else {refreshAgain = true; return}
        let query = GitWorkspaceRequest(); request = query
        for listener in listeners.values {listener.gitChanged(false,false)}
        query.start(directory:path) { [weak self,weak query] result in
            guard let self,let query,self.request === query else {return}
            self.request = nil
            let old = self.repositories, oldFailure = self.failure, oldObservation = self.observationFailure, hadBaseline = self.hasBaseline
            var meaningful = false
            switch result {
            case .success(let value):
                meaningful = hadBaseline && old != value
                self.hasBaseline = true; self.repositories = value; self.failure = nil
                self.updateSpaces(Set(value.compactMap(\.status).flatMap {[$0.remoteSpace,$0.pushSpace].compactMap {$0}}))
                do {
                    try self.observation.update(paths:value.flatMap {$0.status?.observationPaths ?? [$0.root]})
                    self.observationFailure = nil
                } catch {self.observationFailure = error.localizedDescription}
            case .failure(let error):self.failure = error.localizedDescription
            }
            let changed = !hadBaseline || old != self.repositories || oldFailure != self.failure || oldObservation != self.observationFailure
            for listener in self.listeners.values {listener.gitChanged(changed,meaningful)}
            if self.refreshAgain {self.refreshAgain = false; self.scheduleRefresh()}
        }
    }
    private func updateSpaces(_ next:Set<HuggingFaceSpace>) {
        guard next != spaces else {return}
        for space in spaces.subtracting(next) {
            spaceRequests.removeValue(forKey:space)?.task.cancel()
            spaceStatuses.removeValue(forKey:space)
        }
        spaces = next
        refreshSpaces()
    }
    private func refreshSpaces() {
        spaceRefresh?.cancel(); spaceRefresh = nil
        guard !spaces.isEmpty else {return}
        for space in spaces where spaceRequests[space] == nil {
            let token = UUID()
            let task = space.requestStatus { [weak self] result in
                guard let self,self.spaceRequests[space]?.token == token else {return}
                self.spaceRequests.removeValue(forKey:space)
                guard self.spaceStatuses.updateValue(result,forKey:space) != result else {return}
                for listener in self.listeners.values {listener.spaceChanged()}
            }
            spaceRequests[space] = (token,task)
            task.resume()
        }
        let work = DispatchWorkItem { [weak self] in self?.refreshSpaces() }
        spaceRefresh = work
        DispatchQueue.main.asyncAfter(deadline:.now()+30,execute:work)
    }
}
