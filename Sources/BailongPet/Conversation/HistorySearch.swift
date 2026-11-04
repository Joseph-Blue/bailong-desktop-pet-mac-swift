import Foundation

enum HistorySearch {
    static func ranges(in text:String, query:String) -> [NSRange] {
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else {return []}
        let source = text as NSString
        var result = [NSRange](), start = 0
        while start < source.length {
            let match = source.range(of:query,options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],range:NSRange(location:start,length:source.length-start),locale:.current)
            guard match.location != NSNotFound, match.length > 0 else {break}
            result.append(match); start = NSMaxRange(match)
        }
        return result
    }
    static func excerpt(_ text:String, around range:NSRange) -> String {
        let source = text as NSString
        let start = max(0,range.location-18), end = min(source.length,NSMaxRange(range)+48)
        let safe = source.rangeOfComposedCharacterSequences(for:NSRange(location:start,length:end-start))
        return (start > 0 ? "…" : "")+source.substring(with:safe).replacingOccurrences(of:"\n",with:" ")+(end < source.length ? "…" : "")
    }
    static func snippet(_ conversation:Conversation, query:String) -> String? {
        guard !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return nil}
        for turn in conversation.turns {
            for (name,text) in [("你",turn.input),("思考摘要",turn.summary),("执行记录",turn.steps),("回复",turn.messages),("回复",turn.final),("文件",(turn.fileEdits ?? []).map(\.path).joined(separator:"\n"))] {
                if let match = ranges(in:text,query:query).first {return name+" · "+excerpt(text,around:match)}
            }
        }
        return ranges(in:conversation.title,query:query).isEmpty ? nil : "标题匹配"
    }
    static func filter(_ conversations:[Conversation], query:String) -> [Conversation] {
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else {return conversations}
        return conversations.filter { conversation in
            if !ranges(in:conversation.title,query:query).isEmpty {return true}
            return conversation.turns.contains { turn in
                ([turn.input,turn.messages,turn.final,turn.summary,turn.steps] + (turn.fileEdits ?? []).map(\.path)).contains {!ranges(in:$0,query:query).isEmpty}
            }
        }
    }
}
