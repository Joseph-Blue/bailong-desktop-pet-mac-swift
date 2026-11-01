import Foundation
import CoreGraphics

// 使用屏幕可用区域和角色可见边界；已有方向仍放得下时不来回翻转。
enum BubblePlacement {
    enum Side:CaseIterable {case left,right,above,below}
    struct Result {let frame:CGRect; let side:Side}
    static func resolve(size:CGSize,pet:CGRect,screen:CGRect,preferred:[Side],previous:Side?) -> Result {
        let area = screen.insetBy(dx:8,dy:8)
        let size = CGSize(width:min(size.width,area.width),height:min(size.height,area.height))
        let gap:CGFloat = 10
        var order = preferred
        if let previous {order.removeAll {$0 == previous}; order.insert(previous,at:0)}
        for side in Side.allCases where !order.contains(side) {order.append(side)}
        let avoid = pet.insetBy(dx:-4,dy:-4)
        var best:Result?, bestOverlap = CGFloat.greatestFiniteMagnitude
        for side in order {
            var origin:CGPoint
            switch side {
            case .left: origin = CGPoint(x:pet.minX-gap-size.width,y:pet.midY-size.height/2)
            case .right: origin = CGPoint(x:pet.maxX+gap,y:pet.midY-size.height/2)
            case .above: origin = CGPoint(x:pet.midX-size.width/2,y:pet.maxY+gap)
            case .below: origin = CGPoint(x:pet.midX-size.width/2,y:pet.minY-gap-size.height)
            }
            origin.x = max(area.minX,min(origin.x,area.maxX-size.width))
            origin.y = max(area.minY,min(origin.y,area.maxY-size.height))
            let frame = CGRect(origin:origin,size:size), intersection = frame.intersection(avoid)
            let overlap = intersection.isNull ? 0 : intersection.width*intersection.height
            let result = Result(frame:frame,side:side)
            if overlap == 0 {return result}
            if overlap < bestOverlap {best = result; bestOverlap = overlap}
        }
        return best!
    }
}
