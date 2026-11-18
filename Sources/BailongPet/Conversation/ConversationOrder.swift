import Foundation

// 相同时间按原集合靠后的会话优先。历史窗口关闭时可释放整份排序。
struct ConversationOrder {
    private struct Rank: Equatable, Comparable {
        let date: Date
        let offset: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.date == rhs.date ? lhs.offset < rhs.offset : lhs.date < rhs.date
        }
    }

    private var ranks = [ObjectIdentifier: Rank]()
    private(set) var conversations = [Conversation]()

    mutating func update(_ source: [Conversation]) {
        let next = Dictionary(uniqueKeysWithValues:source.enumerated().map { offset, conversation in
            (ObjectIdentifier(conversation), Rank(date:conversation.lastActivity,offset:offset))
        })
        guard next != ranks else {return}
        ranks = next
        conversations = source.sorted {next[ObjectIdentifier($0)]! > next[ObjectIdentifier($1)]!}
    }

    // 流式正文只改变本会话的最新消息时间。时钟回拨时重算该会话的最大值。
    mutating func messageChanged(in conversation: Conversation, from previous: Date?, to date: Date) -> Bool {
        let id = ObjectIdentifier(conversation)
        guard let old = ranks[id] else {return false}
        let activity = previous.map {date < $0} == true ? conversation.lastActivity : max(old.date,date)
        guard activity != old.date else {return false}
        let rank = Rank(date:activity,offset:old.offset)
        ranks[id] = rank
        guard let index = conversations.firstIndex(where:{$0 === conversation}) else {return false}
        let followsPrevious = index == 0 || ranks[ObjectIdentifier(conversations[index-1])]! > rank
        let precedesNext = index+1 == conversations.count || rank > ranks[ObjectIdentifier(conversations[index+1])]!
        guard !followsPrevious || !precedesNext else {return false}
        conversations.remove(at:index)
        let position = conversations.firstIndex {ranks[ObjectIdentifier($0)]! < rank} ?? conversations.endIndex
        conversations.insert(conversation,at:position)
        return true
    }
}
