import AppKit

@main
struct HistorySelectionRegression {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let ui = ChatInterface()
        let first = Conversation(), selected = Conversation(), external = Conversation()
        first.title = "较早的内置对话"; selected.title = "当前内置对话"
        external.title = "新观察到的外部对话"; external.external = true
        var conversations = [first, selected, external]
        var current = selected
        var selections = [String]()
        func check(_ valid: Bool, _ message: String) {
            if !valid { fputs("失败：\(message)\n",stderr); exit(1) }
        }
        ui.onSelect = { key in
            selections.append(key)
            // 旧版会在这里递归；到第九次即报告失败，避免再次耗尽主线程栈。
            check(selections.count <= 8, "列表刷新反复回调选中事件")
            current = conversations.first(where:{$0.key == key})!
            ui.refresh(conversations,selected:current,busy:false)
        }
        ui.refresh(conversations,selected:current,busy:false)
        check(selections.isEmpty, "初次刷新把程序选中操作当成了用户切换")
        check(ui.list.selectedRow == 1 && ui.selected == selected.key, "未保留当前内置对话")

        ui.list.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
        check(selections == [first.key] && current === first, "用户选择应只回调一次")
        ui.refresh(conversations,selected:current,busy:true)
        check(selections.count == 1 && ui.list.selectedRow == 2, "状态刷新改变了选择")

        let newest = Conversation(); newest.external = true
        conversations.append(newest)
        ui.refresh(conversations,selected:current,busy:false)
        check(selections.count == 1 && ui.list.selectedRow == 3, "新增外部会话后未按会话 ID 恢复选择")

        ui.list.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
        check(selections == [first.key,newest.key] && current === newest, "刷新后仍应允许用户选择其他对话")
        print("通过：初次载入、用户选择、状态刷新、新增会话后恢复选择。")
    }
}
