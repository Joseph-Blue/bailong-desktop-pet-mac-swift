import Foundation

// 内置轮次的公开消息与进展快照，不持有窗口、连接或持久化对象。
final class TaskMessageAccumulator {
    private var messages = [String:String](), messageOrder = [String](), summaries = [String:String](), steps = [String:String]()
    private var previewedMessages = [String:String]()
    private(set) var finalMessageID:String?
    private var imageMessageIDs = Set<String>()
    private(set) var currentActivity:TaskActivity?
    private var activityItems = [[String:Any]]()
    private var finalText:String?
    private var editsByItem = [String:[FileEditSummary]](), editOrder = [String]()
    var imageLinks:[String] {messageOrder.filter {imageMessageIDs.contains($0)}.compactMap {messages[$0]}}
    func clearActivity() {currentActivity = nil; activityItems.removeAll()}
    func finalize(_ turn:Turn) {
        if turn.final.isEmpty {finalMessageID = messageOrder.last(where:{!imageMessageIDs.contains($0)}); turn.final = finalMessageID.flatMap {messages[$0]} ?? ""}
    }
    func takeChangedMessages() -> [(id:String,text:String)] {
        var changed = [(id:String,text:String)]()
        for id in messageOrder where id != finalMessageID {
            guard let text = messages[id],!text.isEmpty,previewedMessages[id] != text else {continue}
            previewedMessages[id] = text; changed.append((id,text))
        }
        return changed
    }
    func receive(_ method:String,_ p:[String:Any]) -> Bool {
        switch method {
        case "item/agentMessage/delta":
            guard let id = p["itemId"] as? String else {return false}; if messages[id] == nil {messageOrder.append(id)}
            messages[id,default:""] += p["delta"] as? String ?? ""
            updateActivity(["id":id,"type":"agentMessage"])
        case "item/reasoning/summaryTextDelta":
            let key = "\(p["itemId"] ?? ""):\(p["summaryIndex"] ?? 0)"; summaries[key,default:""] += p["delta"] as? String ?? ""
            updateActivity(["id":p["itemId"] as? String ?? "","type":"reasoning","summary":summaries.filter {$0.key.hasPrefix("\(p["itemId"] ?? ""):")}.sorted {$0.key < $1.key}.map(\.value)])
        case "item/started", "item/completed": if let item = p["item"] as? [String:Any] {
            record(item)
            let type = item["type"] as? String ?? ""
            if type != "agentMessage" && !(type == "imageGeneration" && imageMessageIDs.contains(item["id"] as? String ?? "")) {
                var progress = item
                progress["status"] = item["status"] as? String ?? (method == "item/started" ? "inProgress" : "completed")
                if type == "reasoning",TaskActivity.summary(item["summary"] as? [Any] ?? []).isEmpty,let id = item["id"] as? String {
                    progress["summary"] = summaries.filter {$0.key.hasPrefix(id+":")}.sorted {$0.key < $1.key}.map(\.value)
                }
                updateActivity(progress)
            } else if type == "agentMessage" {
                updateActivity(item)
            }
        }
        case "turn/plan/updated": steps["plan"] = (p["plan"] as? [[String:Any]] ?? []).map { "\($0["status"] ?? "") · \($0["step"] ?? "")" }.joined(separator:"\n"); currentActivity = .init(title:"正在更新计划",detail:steps["plan"] ?? "")
        default:return false
        }
        return true
    }
    private func updateActivity(_ item:[String:Any]) {
        guard let id = item["id"] as? String else {return}
        let projected = DesktopRuntimeProjection.item(item)
        if let index = activityItems.firstIndex(where:{$0["id"] as? String == id}) {activityItems[index] = projected}
        else {activityItems.append(projected)}
        currentActivity = TaskActivity.current(items:activityItems)
    }
    func record(_ item: [String:Any]) {
        let id = item["id"] as? String ?? UUID().uuidString
        switch item["type"] as? String {
        case "agentMessage":
            currentActivity = nil
            if messages[id] == nil {messageOrder.append(id)}; messages[id] = item["text"] as? String ?? ""
            if item["phase"] as? String == "final_answer" {finalMessageID = id; finalText = item["text"] as? String ?? ""}
        case "imageGeneration":
            if let link = GeneratedImageLink.markdown(status:item["status"] as? String,savedPath:item["savedPath"] as? String) {
                if messages[id] == nil {messageOrder.append(id)}
                messages[id] = link; imageMessageIDs.insert(id); steps.removeValue(forKey:id)
                currentActivity = nil
            } else if ["inProgress","running"].contains(item["status"] as? String ?? "") {
                steps[id] = "正在生成图片"
            } else {steps.removeValue(forKey:id)}
        case "reasoning":
            // 只读取协议公开 summary，不读取 content 或加密推理字段。
            for (index,part) in (item["summary"] as? [Any] ?? []).enumerated() {summaries["\(id):\(index)"] = part as? String ?? (part as? [String:Any])?["text"] as? String ?? ""}
        case "commandExecution": steps[id] = CommandSummary.text(item)
        case "fileChange":
            if editsByItem[id] == nil {editOrder.append(id)}
            editsByItem[id] = FileEditSummary.read(item)
            steps.removeValue(forKey:id)
        case "mcpToolCall", "dynamicToolCall": steps[id] = "\(item["status"] ?? "") · \(item["tool"] ?? "工具")"
        case "webSearch": steps[id] = "搜索：\(item["query"] ?? "")"
        default:break
        }
    }
    func apply(to turn:Turn) {
        let text = messageOrder.compactMap{messages[$0]}.joined(separator:"\n\n")
        if turn.messages != text {turn.lastMessageAt = Date(); turn.messages = text}
        if let finalText {turn.final = finalText}
        turn.summary = summaries.sorted{$0.key<$1.key}.map{$0.value}.joined(separator:"\n")
        turn.steps = steps.sorted{$0.key<$1.key}.map{$0.value}.joined(separator:"\n\n")
        turn.fileEdits = FileEditSummary.merged(editOrder.flatMap {editsByItem[$0] ?? []})
    }
}
