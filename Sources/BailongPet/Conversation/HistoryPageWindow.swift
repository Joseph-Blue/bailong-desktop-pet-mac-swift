import Foundation

// 只呈现一页；翻页替换正文，不将此前页面追加进 TextKit。
struct HistoryPageWindow {
    static let size = 20
    private var start = 0
    private(set) var followsLatest = true
    func range(count:Int) -> Range<Int> {
        let lower = followsLatest ? max(0,count-Self.size) : min(start,max(0,count-1))
        return lower..<min(count,lower+Self.size)
    }
    mutating func move(_ direction:Int,count:Int) {
        start = max(0,min(max(0,count-Self.size),range(count:count).lowerBound+direction*Self.size))
        followsLatest = start == max(0,count-Self.size)
    }
    mutating func reveal(_ index:Int) {start = max(0,index/Self.size*Self.size); followsLatest = false}
}
