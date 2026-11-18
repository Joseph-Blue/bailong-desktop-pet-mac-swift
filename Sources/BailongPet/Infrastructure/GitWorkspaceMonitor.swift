import Foundation

// 同一目录的可见信息栏共用一次只读查询和一份文件监听，最后一个入口退出时释放。
final class GitWorkspaceMonitor {
    private static var directories = [String:GitWorkspaceMonitor]()
    static func directory(_ path:String) -> GitWorkspaceMonitor {
        if let monitor = directories[path] {return monitor}
        let monitor = GitWorkspaceMonitor(path:path); directories[path] = monitor
        return monitor
    }
    private let path:String, observation = GitWorkspaceObservation()
    private var listeners = [ObjectIdentifier:(Bool,Bool) -> Void]()
    private var pending:DispatchWorkItem?, request:GitWorkspaceRequest?
    private var refreshAgain = false
    private(set) var snapshot:GitWorkspaceStatus?, failure:String?, observationFailure:String?
    private(set) var hasBaseline = false
    var loading:Bool {request != nil}
    private init(path:String) {
        self.path = path
        observation.onChange = { [weak self] in self?.scheduleRefresh() }
    }
    func attach(_ owner:AnyObject,changed:@escaping (Bool,Bool) -> Void) {
        listeners[ObjectIdentifier(owner)] = changed
        if listeners.count == 1 {refresh()}
    }
    func detach(_ owner:AnyObject) {
        listeners.removeValue(forKey:ObjectIdentifier(owner))
        if listeners.isEmpty {
            pending?.cancel(); request?.cancel(); request = nil; observation.stop()
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
        for listener in listeners.values {listener(false,false)}
        query.start(directory:path) { [weak self,weak query] result in
            guard let self,let query,self.request === query else {return}
            self.request = nil
            let old = self.snapshot, oldFailure = self.failure, oldObservation = self.observationFailure, hadBaseline = self.hasBaseline
            var meaningful = false
            switch result {
            case .success(let value):
                meaningful = hadBaseline && old != value
                self.hasBaseline = true; self.snapshot = value; self.failure = nil
                do {
                    try self.observation.update(paths:value?.observationPaths ?? [])
                    self.observationFailure = nil
                } catch {self.observationFailure = error.localizedDescription}
            case .failure(let error):self.failure = error.localizedDescription
            }
            let changed = !hadBaseline || old != self.snapshot || oldFailure != self.failure || oldObservation != self.observationFailure
            for listener in self.listeners.values {listener(changed,meaningful)}
            if self.refreshAgain {self.refreshAgain = false; self.scheduleRefresh()}
        }
    }
}
