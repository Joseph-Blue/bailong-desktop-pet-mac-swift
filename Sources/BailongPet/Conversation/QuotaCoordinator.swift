import AppKit

final class QuotaCoordinator {
    private let pet:PetController, connection:CodexConnection
    private let isClosing:() -> Bool
    private var quotaSerial = 0, quotaRequestInFlight = false
    private var quotaAccount:[String:Any]?
    init(pet:PetController,connection:CodexConnection,isClosing:@escaping () -> Bool) {
        self.pet = pet; self.connection = connection; self.isClosing = isClosing
    }
    func query() {
        guard !(quotaRequestInFlight && pet.quotaActive) else {return}
        quotaRequestInFlight = true; pet.quotaActive = true; quotaSerial += 1; let serial = quotaSerial
        quotaAccount = nil
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
        quotaRequestInFlight = false
        switch result {
        case .failure(let error):
            pet.quotaActive = false
            pet.say("Codex 额度",body:" ",kind:"quota")
            pet.bubble.quotaRows(QuotaPresentation.unavailable(account:quotaAccount),scale:Double(pet.bubblePercent)/100,
                failure:AppFailure.codex(error.localizedDescription),retry:{ [weak self] in self?.query() })
            pet.placeBubble()
        case .success(let value):
            let overview = QuotaPresentation.overview(value,account:quotaAccount)
            if pet.bubble.kind != "quota" {pet.say("Codex 额度",body:" ",kind:"quota")}
            pet.bubble.quotaRows(overview,scale:Double(pet.bubblePercent)/100); pet.placeBubble()
        }
    }

}
