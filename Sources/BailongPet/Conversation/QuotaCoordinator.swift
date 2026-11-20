import AppKit

final class QuotaCoordinator {
    private struct CachedQuota {
        let snapshot:QuotaQuery.Snapshot
        let connectionGeneration:Int

        func isFresh(seconds:TimeInterval,now:Date = Date()) -> Bool {
            let age = now.timeIntervalSince(snapshot.fetchedAt)
            guard age >= 0,age < seconds else {return false}
            let value = snapshot.value
            let map = value["rateLimitsByLimitId"] as? [String:[String:Any]] ?? [:]
            let buckets = map.isEmpty ? (value["rateLimits"] as? [String:Any]).map {[$0]} ?? [] : Array(map.values)
            let resets = buckets.flatMap {bucket in
                ["primary","secondary","individualLimit"].compactMap {key in
                    QuotaPresentation.number((bucket[key] as? [String:Any])?["resetsAt"])
                }
            }
            let expirations = QuotaResetCards(value).expirations.compactMap {expiration -> Double? in
                if case .date(let date) = expiration {return date.timeIntervalSince1970}
                return nil
            }
            return (resets+expirations).allSatisfy {$0 > now.timeIntervalSince1970}
        }
    }
    private let pet:PetController, connection:CodexConnection
    private let directory:() -> String?
    private let isClosing:() -> Bool
    private let localUsage = LocalDailyTokenReader()
    private var quotaSerial = 0, quotaRequestInFlight = false
    private var quotaAccount:[String:Any]?
    private var apiProvider:APIProviderIdentity?
    private var quotaValue:Result<[String:Any],Error>?
    private var dailyUsage = DailyTokenUsage.loading
    private var presented = false, localUsageRequested = false
    private var cachedQuota:CachedQuota?
    private var cachedAPIProviderUsage:APIProviderUsageCache?
    private var cachedAt:Date?
    private var cacheGeneration = 0
    private var preferencesObserver:NSObjectProtocol?
    init(pet:PetController,connection:CodexConnection,directory:@escaping () -> String?,isClosing:@escaping () -> Bool) {
        self.pet = pet; self.connection = connection; self.directory = directory; self.isClosing = isClosing
        preferencesObserver = NotificationCenter.default.addObserver(forName:PetPreferences.didChange,object:pet.preferences,queue:.main) { [weak self] note in
            let keys = note.userInfo?["keys"] as? [String] ?? []
            guard keys.contains("quotaCacheEnabled") || keys.contains("quotaCacheSeconds"),let self else {return}
            self.cachedQuota = nil; self.cachedAPIProviderUsage = nil; self.cacheGeneration += 1
        }
    }
    deinit {
        if let preferencesObserver {NotificationCenter.default.removeObserver(preferencesObserver)}
    }
    func cancel() {
        quotaSerial += 1; quotaRequestInFlight = false; quotaAccount = nil; apiProvider = nil; quotaValue = nil
        cachedQuota = nil; cachedAPIProviderUsage = nil; cachedAt = nil; cacheGeneration += 1
        if pet.quotaActive && pet.bubble.kind.hasPrefix("quota") {pet.bubble.hide()}
        pet.quotaActive = false
    }

    func query(forceRefresh:Bool = false) {
        guard !(quotaRequestInFlight && pet.quotaActive) else {return}
        quotaRequestInFlight = true; pet.quotaActive = true; quotaSerial += 1; let serial = quotaSerial
        quotaAccount = nil; apiProvider = nil; quotaValue = nil; cachedAt = nil; dailyUsage = .loading; presented = false; localUsageRequested = false
        let cacheGeneration = self.cacheGeneration
        if forceRefresh {cachedQuota = nil; cachedAPIProviderUsage = nil}
        if pet.dock == nil {pet.play(pet.catalog.quotaAnimation,"quota")}
        pet.say(pet.preferences.statusLine("quotaLoadingTemplate"),kind:"quotaLoading",personalizeTitle:false,userRequested:true)
        connection.connect { [weak self] error in
            guard let self else{return}
            if let error {self.quotaResult(serial,.failure(error));return}
            guard serial == self.quotaSerial, self.pet.quotaActive, !self.isClosing() else {return}
            self.readAPIProvider(serial) { provider in
                guard serial == self.quotaSerial,self.pet.quotaActive,!self.isClosing() else {return}
                if let provider {
                    self.apiProvider = provider
                    if !forceRefresh,let usage = self.cachedAPIProviderUsage?.reusable(
                        provider:provider,generation:cacheGeneration,
                        enabled:self.pet.preferences.bool("quotaCacheEnabled"),
                        seconds:self.pet.preferences.number("quotaCacheSeconds")) {
                        self.dailyUsage = usage
                        self.cachedAt = self.cachedAPIProviderUsage?.fetchedAt
                        self.quotaResult(serial,.success([:]),loadUsage:false)
                        return
                    }
                    self.quotaResult(serial,.success([:]))
                    return
                }
                self.continueSubscriptionQuery(serial,cacheGeneration:cacheGeneration,forceRefresh:forceRefresh)
            }
        }
    }
    private func readAPIProvider(_ serial:Int,_ completion:@escaping (APIProviderIdentity?) -> Void) {
        var params:[String:Any] = ["includeLayers":false]
        if let directory = directory()?.trimmingCharacters(in:.whitespacesAndNewlines),!directory.isEmpty {params["cwd"] = directory}
        connection.call("config/read",params) { result in
            guard serial == self.quotaSerial else {return}
            guard case .success(let value) = result,let config = value["config"] as? [String:Any] else {
                completion(nil);return
            }
            completion(APIProviderDirectory.thirdParty(in:config))
        }
    }
    private func continueSubscriptionQuery(_ serial:Int,cacheGeneration:Int,forceRefresh:Bool) {
        guard serial == quotaSerial,pet.quotaActive,!isClosing() else {return}
            if !forceRefresh,let cached = self.freshCache() {
                // 只复用同一连接、同一账号的额度；不读取登录文件或凭证。
                self.connection.call("account/read",["refreshToken":false]) { [weak self] result in
                    guard let self,serial == self.quotaSerial,self.pet.quotaActive,!self.isClosing() else {return}
                    switch result {
                    case .failure(let error):
                        self.cachedQuota = nil; self.quotaResult(serial,.failure(error))
                    case .success(let response):
                        if cacheGeneration == self.cacheGeneration,self.freshCache() != nil,
                           let account = response["account"] as? [String:Any],let previous = cached.snapshot.account,
                           NSDictionary(dictionary:previous).isEqual(to:account) {
                            self.quotaAccount = account; self.cachedAt = cached.snapshot.fetchedAt
                            self.quotaResult(serial,.success(cached.snapshot.value))
                        } else {self.requestQuota(serial,cacheGeneration:cacheGeneration)}
                    }
                }
            } else {self.requestQuota(serial,cacheGeneration:cacheGeneration)}
    }
    private func freshCache() -> CachedQuota? {
        guard pet.preferences.bool("quotaCacheEnabled"),let cachedQuota,connection.isConnected,
              cachedQuota.connectionGeneration == connection.connectionGeneration,
              cachedQuota.isFresh(seconds:pet.preferences.number("quotaCacheSeconds")) else {
            cachedQuota = nil; return nil
        }
        return cachedQuota
    }
    private func requestQuota(_ serial:Int,cacheGeneration:Int) {
        cachedQuota = nil
        let connectionGeneration = connection.connectionGeneration
        let query = QuotaQuery { [weak self] result in
            guard let self,serial == self.quotaSerial,self.pet.quotaActive,!self.isClosing() else {return}
            switch result {
            case .success(let snapshot):
                self.quotaAccount = snapshot.account
                if self.apiProvider == nil,self.pet.preferences.bool("quotaCacheEnabled"),cacheGeneration == self.cacheGeneration,
                   connectionGeneration == self.connection.connectionGeneration,snapshot.account != nil {
                    self.cachedQuota = CachedQuota(snapshot:snapshot,connectionGeneration:connectionGeneration)
                }
                self.quotaResult(serial,.success(snapshot.value))
            case .failure(let error):self.quotaResult(serial,.failure(error))
            }
        }
        query.start { [connection = self.connection] method,params,reply in connection.call(method,params,completion:reply) }
    }
    func quotaResult(_ serial: Int, _ result: Result<[String:Any],Error>,loadUsage:Bool = true) {
        guard serial == quotaSerial && pet.quotaActive && !isClosing() else{return}
        quotaRequestInFlight = false; quotaValue = result; render(serial)
        guard loadUsage else {localUsageRequested = true; return}
        guard !localUsageRequested else {return}
        localUsageRequested = true
        // 先排版额度与账号信息，下一次主队列调度再启动本机日志读取。
        DispatchQueue.main.async { [weak self] in
            guard let self,serial == self.quotaSerial,self.pet.quotaActive,!self.isClosing(),
                  self.pet.bubble.visible,self.pet.bubble.kind == "quota" else {return}
            let provider = self.apiProvider
            self.localUsage.query(provider:provider?.id) { [weak self] usage in
                guard let self,serial == self.quotaSerial,self.pet.quotaActive,!self.isClosing() else {return}
                self.dailyUsage = usage
                if let provider,self.pet.preferences.bool("quotaCacheEnabled"),usage.usage != nil {
                    self.cachedAPIProviderUsage = APIProviderUsageCache(provider:provider,usage:usage,
                        fetchedAt:Date(),generation:self.cacheGeneration)
                }
                self.render(serial)
            }
        }
    }
    private func render(_ serial:Int) {
        guard serial == quotaSerial,pet.quotaActive,!isClosing(),let result = quotaValue else {return}
        // 同次回执只更新仍在显示的额度页，不重开已关闭或被替换的气泡。
        if presented && (!pet.bubble.visible || pet.bubble.kind != "quota") {return}
        var overview:QuotaOverview
        var failure:AppFailure?
        if let apiProvider {
            overview = QuotaPresentation.api(apiProvider,usage:dailyUsage)
        } else {
            switch result {
            case .success(let value):overview = QuotaPresentation.overview(value,account:quotaAccount)
            case .failure(let error):
                overview = QuotaPresentation.unavailable(account:quotaAccount)
                failure = AppFailure.codex(error.localizedDescription)
            }
        }
        if apiProvider == nil {
            overview.rows.append(QuotaRow(title:"今日用量",value:dailyUsage.value,detail:dailyUsage.detail,remaining:nil,retry:dailyUsage.failed,wrapsValue:true,loading:dailyUsage.isLoading,usage:dailyUsage.usage,subtitle:"（本机日志）"))
        }
        if pet.bubble.kind != "quota" {pet.say("Codex 额度",body:" ",kind:"quota")}
        let preserveScroll = presented
        presented = true
        pet.bubble.quotaRows(overview,scale:Double(pet.bubblePercent)/100,failure:failure,cachedAt:cachedAt,retry:{ [weak self] in self?.query(forceRefresh:true) },preserveScroll:preserveScroll)
        pet.placeBubble()
    }
}
