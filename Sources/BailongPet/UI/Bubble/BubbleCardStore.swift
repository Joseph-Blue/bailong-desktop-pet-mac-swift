import AppKit

// 拥有卡片身份、保留上限与选择规则；不打开窗口或操作滚动视图。
final class BubbleCardStore {
    private(set) var cards = [BubbleCard]()
    private(set) var cardIndex:Int?
    private(set) var isBrowsingCards = false
    var selectedID:String? {cardIndex.map {cards[$0].id}}

    func present(_ message:BubbleCard,select:Bool,limit:Int,wasVisible:Bool,protectsInput:Bool,pendingAttention:Bool) -> Bool {
        let currentID = selectedID
        if let index = cards.firstIndex(where:{$0.id == message.id}) {
            var updated = message
            if let old = cards[index].approval,let new = message.approval,old.request.identity == new.request.identity,old.request.details == new.request.details {updated.approval = old}
            if message.question?.submit != nil {
                updated.form = cards[index].form; updated.questionSize = cards[index].questionSize
            }
            if message.showsTaskOverview {cards.remove(at:index); cards.append(updated)}
            else {cards[index] = updated}
        } else {cards.append(message)}
        // 只保留本次运行的近期卡片；等待回答的卡片和正在阅读的卡片不被裁掉。
        while cards.count > limit,let old = cards.firstIndex(where:{$0.id != currentID && $0.id != message.id && !$0.attentionAction}) {cards.remove(at:old)}
        cardIndex = currentID.flatMap {id in cards.firstIndex(where:{$0.id == id})}
        let current = cardIndex.map {cards[$0]}
        // 概览与随机台词让位于任务消息；阅读对话、填写及提交问卷时不自动切卡。
        let protectsCurrent = protectsInput || (isBrowsingCards && current?.priority != .companion)
        let replacesCurrent = current.map {
            message.priority.rawValue > $0.priority.rawValue ||
            (message.priority == $0.priority && message.priority != .request)
        } ?? false
        // 主动发送或按键召回概览可选中新卡，但不打断待处理请求或问卷。
        let requestedCard = (select || message.showsTaskOverview) && !pendingAttention && !protectsInput
        if !wasVisible || cardIndex == nil || requestedCard || (!protectsCurrent && replacesCurrent) {
            if currentID != message.id {isBrowsingCards = false}
            cardIndex = cards.firstIndex(where:{$0.id == message.id})
            return true
        }
        return currentID == message.id
    }
    func remove(where predicate:(BubbleCard) -> Bool) {
        let id = selectedID
        cards.removeAll(where:predicate)
        cardIndex = id.flatMap {id in cards.firstIndex {$0.id == id}}
    }
    func applyLimit(_ limit:Int,showOverview:Bool) {
        let id = selectedID
        if !showOverview {remove {$0.showsTaskOverview}}
        while cards.count > limit,let old = cards.firstIndex(where:{$0.id != id && !$0.attentionAction}) {cards.remove(at:old)}
        cardIndex = id.flatMap {id in cards.firstIndex {$0.id == id}}
    }
    func saveForm(_ form:QuestionForm?,size:NSSize?) {
        guard let index = cardIndex else {return}
        cards[index].form = form; cards[index].questionSize = size
    }
    func clearQuestionSizes() {for index in cards.indices {cards[index].questionSize = nil}}
    func navigate(_ delta:Int) -> Bool {
        guard let index = cardIndex,cards.indices.contains(index+delta) else {return false}
        isBrowsingCards = true; cardIndex = index+delta; return true
    }
    func clearSelection() {cardIndex = nil; isBrowsingCards = false}
    func stopBrowsing() {isBrowsingCards = false}
    func finishTask(_ key:String,status:String) {
        for index in cards.indices where cards[index].timing?.key == key && cards[index].timing?.finished == nil {
            cards[index].timing?.finished = Date(); cards[index].timing?.status = status
            cards[index].animateHeading = false
        }
    }
}
