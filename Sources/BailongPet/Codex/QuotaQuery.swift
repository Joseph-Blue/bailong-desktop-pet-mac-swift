import Foundation

/// 汇合同一次查询的回执；跨次缓存由 QuotaCoordinator 管理。
final class QuotaQuery {
    typealias Reply = (Result<[String:Any],Error>) -> Void
    typealias Call = (String,[String:Any],@escaping Reply) -> Void
    struct Snapshot {
        let value: [String:Any]
        let account: [String:Any]?
        let fetchedAt: Date
    }
    private var account: [String:Any]?
    private var value: [String:Any]?
    private var fetchedAt: Date?
    private let update: (Result<Snapshot,Error>) -> Void

    init(update: @escaping (Result<Snapshot,Error>) -> Void) { self.update = update }

    func start(call: Call) {
        // 额度立即发出，账号仅补充套餐显示，不作为额度请求的前置条件。
        call("account/rateLimits/read",[:]) { [self] result in
            switch result {
            case .success(let value):
                self.value = value
                self.fetchedAt = Date()
                publish()
            case .failure(let error): update(.failure(error))
            }
        }
        call("account/read",["refreshToken":false]) { [self] result in
            guard case .success(let response) = result,
                  let account = response["account"] as? [String:Any] else {return}
            self.account = account
            // 账号晚到只补齐同一次查询的套餐，不等待它，也不重放加载动画。
            publish()
        }
    }

    private func publish() {
        if let value,let fetchedAt {update(.success(Snapshot(value:value,account:account,fetchedAt:fetchedAt)))}
    }
}
