import Foundation
import CoreGraphics

// 使用屏幕可用区域和角色可见边界；已有方向仍放得下时不来回翻转。
enum BubblePlacement {
    enum Side:CaseIterable {case left,right,above,below}
    struct Result {let frame:CGRect; let side:Side}
    private static let gap:CGFloat = 10

    static func interpolatedAnchor(from expanded:CGRect,to docked:CGRect,progress:CGFloat) -> CGRect {
        CGRect(x:expanded.minX+(docked.minX-expanded.minX)*progress,
               y:expanded.minY+(docked.minY-expanded.minY)*progress,
               width:expanded.width+(docked.width-expanded.width)*progress,
               height:expanded.height+(docked.height-expanded.height)*progress)
    }

    static func originX(width:CGFloat,side:Side,pet:CGRect,area:CGRect) -> CGFloat {
        let x:CGFloat
        switch side {
        case .left: x = pet.minX-gap-width
        case .right: x = pet.maxX+gap
        case .above,.below: x = pet.midX-width/2
        }
        return max(area.minX,min(x,area.maxX-width))
    }

    static func resolve(size:CGSize,pet:CGRect,screen:CGRect,preferred:[Side],previous:Side?,avoiding:[CGRect] = [],allowsSideFallback:Bool = true) -> Result {
        let area = screen.insetBy(dx:8,dy:8)
        let size = CGSize(width:min(size.width,area.width),height:min(size.height,area.height))
        var order = preferred
        if let previous {order.removeAll {$0 == previous}; order.insert(previous,at:0)}
        if allowsSideFallback {for side in Side.allCases where !order.contains(side) {order.append(side)}}
        let avoid = pet.insetBy(dx:-4,dy:-4)
        var best:Result?, bestOverlap = CGFloat.greatestFiniteMagnitude
        for side in order {
            let y:CGFloat
            switch side {
            case .left,.right: y = pet.midY-size.height/2
            case .above: y = pet.maxY+gap
            case .below: y = pet.minY-gap-size.height
            }
            let origin = CGPoint(x:originX(width:size.width,side:side,pet:pet,area:area),
                                 y:max(area.minY,min(y,area.maxY-size.height)))
            let frame = CGRect(origin:origin,size:size), intersection = frame.intersection(avoid)
            let overlap = (intersection.isNull ? 0 : intersection.width*intersection.height) + avoiding.reduce(CGFloat(0)) {
                let intersection = frame.intersection($1.insetBy(dx:-4,dy:-4))
                return $0 + (intersection.isNull ? 0 : intersection.width*intersection.height)
            }
            let result = Result(frame:frame,side:side)
            if overlap == 0 {return result}
            if overlap < bestOverlap {best = result; bestOverlap = overlap}
        }
        return best!
    }
}
