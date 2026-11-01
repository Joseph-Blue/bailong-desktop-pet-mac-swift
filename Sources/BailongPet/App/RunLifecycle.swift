import Foundation

// 只记一次启动和一次正常退出；没有心跳写盘，也不安装致命信号恢复处理器。
final class RunLifecycle {
    struct UnfinishedRun {
        let started: Date?
        let version: String
    }
    private let defaults: UserDefaults
    private var ownsRecord = false
    init(defaults:UserDefaults = .standard) {self.defaults = defaults}
    func begin(version:String) -> UnfinishedRun? {
        let unfinished: UnfinishedRun?
        if defaults.object(forKey:"runActive") as? Bool == true {
            let old = defaults.string(forKey:"runVersion") ?? ""
            let version = !old.isEmpty && old.range(of:"^[0-9A-Za-z.+-]{1,40}$",options:.regularExpression) != nil ? old : "未知"
            unfinished = UnfinishedRun(started:defaults.object(forKey:"runStarted") as? Date,version:version)
        } else {unfinished = nil}
        defaults.set(version,forKey:"runVersion"); defaults.set(Date(),forKey:"runStarted")
        defaults.set(true,forKey:"runActive"); ownsRecord = true
        return unfinished
    }
    func finish() {
        guard ownsRecord else {return}
        defaults.set(false,forKey:"runActive"); ownsRecord = false
    }
}
