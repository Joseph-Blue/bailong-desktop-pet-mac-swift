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
            let result:String? = autoreleasepool {
                let body = turn.bodyReference.value()
                for (name,text) in [("你",body.input),("思考摘要",body.summary),("执行记录",body.steps),("回复",body.messages),("回复",body.final),("文件",(body.fileEdits ?? []).map(\.path).joined(separator:"\n"))] {
                    if let match = firstRange(in:text,query:query) {return name+" · "+excerpt(text,around:match)}
                }
                return nil
            }
            if let result {return result}
        }
        return ranges(in:conversation.title,query:query).isEmpty ? nil : "标题匹配"
    }
    private static func firstRange(in text:String,query:String) -> NSRange? {
        let source = text as NSString
        let range = source.range(of:query,options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],range:NSRange(location:0,length:source.length),locale:.current)
        return range.location == NSNotFound ? nil : range
    }
    static func matches(_ turn:Turn,query:String) -> Bool {
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else {return false}
        return autoreleasepool {
            let body = turn.bodyReference.value()
            return ([body.input,body.messages,body.final,body.summary,body.steps]+(body.fileEdits ?? []).map(\.path)).contains {firstRange(in:$0,query:query) != nil}
        }
    }
    static func filter(_ conversations:[Conversation], query:String) -> [Conversation] {
        let query = query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else {return conversations}
        return conversations.filter { conversation in
            if !ranges(in:conversation.title,query:query).isEmpty {return true}
            return conversation.turns.contains {matches($0,query:query)}
        }
    }
}
