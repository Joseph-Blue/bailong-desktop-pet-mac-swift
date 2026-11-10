import AppKit

final class QuotaCoordinator {
    private let pet:PetController, connection:CodexConnection
    private let isClosing:() -> Bool
    private let localUsage = LocalDailyTokenReader()
    private var quotaSerial = 0, quotaRequestInFlight = false
    private var quotaAccount:[String:Any]?
    private var quotaValue:Result<[String:Any],Error>?
    private var dailyUsage = DailyTokenUsage.loading
    private var presented = false, localUsageRequested = false
    init(pet:PetController,connection:CodexConnection,isClosing:@escaping () -> Bool) {
        self.pet = pet; self.connection = connection; self.isClosing = isClosing
    }
    func query() {
        guard !(quotaRequestInFlight && pet.quotaActive) else {return}
        quotaRequestInFlight = true; pet.quotaActive = true; quotaSerial += 1; let serial = quotaSerial
        quotaAccount = nil; quotaValue = nil; dailyUsage = .loading; presented = false; localUsageRequested = false
        if pet.dock == nil {pet.play(pet.catalog.quotaAnimation,"quota")}
        pet.say(pet.preferences.statusLine("quotaLoadingTemplate"),kind:"quotaLoading",personalizeTitle:false)
        connection.connect { [weak self] error in
            guard let self else{return}
            if let error {self.quotaResult(serial,.failure(error));return}
            guard serial == self.quotaSerial, self.pet.quotaActive, !self.isClosing() else {return}
            let query = QuotaQuery { [weak self] result in
                guard let self, serial == self.quotaSerial, self.pet.quotaActive, !self.isClosing() else {return}
                switch result {
                case .success(let snapshot):
                    self.quotaAccount = snapshot.account
                    self.quotaResult(serial,.success(snapshot.value))
                case .failure(let error): self.quotaResult(serial,.failure(error))
                }
            }
            query.start { [connection = self.connection] method,params,reply in connection.call(method,params,completion:reply) }
        }
    }
    func quotaResult(_ serial: Int, _ result: Result<[String:Any],Error>) {
        guard serial == quotaSerial && pet.quotaActive && !isClosing() else{return}
        quotaRequestInFlight = false; quotaValue = result; render(serial)
        guard !localUsageRequested else {return}
        localUsageRequested = true
        // 先排版额度与账号信息，下一次主队列调度再启动本机日志读取。
        DispatchQueue.main.async { [weak self] in
            guard let self,serial == self.quotaSerial,self.pet.quotaActive,!self.isClosing(),
                  self.pet.bubble.visible,self.pet.bubble.kind == "quota" else {return}
            self.localUsage.query { [weak self] usage in
                guard let self,serial == self.quotaSerial,self.pet.quotaActive,!self.isClosing() else {return}
                self.dailyUsage = usage; self.render(serial)
            }
        }
    }
    private func render(_ serial:Int) {
        guard serial == quotaSerial,pet.quotaActive,!isClosing(),let result = quotaValue else {return}
        // 同次回执只更新仍在显示的额度页，不重开已关闭或被替换的气泡。
        if presented && (!pet.bubble.visible || pet.bubble.kind != "quota") {return}
        var overview:QuotaOverview
        var failure:AppFailure?
        switch result {
        case .success(let value):overview = QuotaPresentation.overview(value,account:quotaAccount)
        case .failure(let error):
            overview = QuotaPresentation.unavailable(account:quotaAccount)
            failure = AppFailure.codex(error.localizedDescription)
        }
        overview.rows.append(QuotaRow(title:"今日用量（本机日志）",value:dailyUsage.value,detail:dailyUsage.detail,remaining:nil,retry:dailyUsage.failed,wrapsValue:true,loading:dailyUsage.isLoading))
        if pet.bubble.kind != "quota" {pet.say("Codex 额度",body:" ",kind:"quota")}
        presented = true
        pet.bubble.quotaRows(overview,scale:Double(pet.bubblePercent)/100,failure:failure,retry:{ [weak self] in self?.query() })
        pet.placeBubble()
    }
}
