import Foundation
import CoreGraphics

struct PetThrowMotion {
    private static let restitution: CGFloat = 0.65
    private let bounds: CGRect
    private var velocity: CGVector
    private var previousTime: TimeInterval
    private var grounded: Bool
    private(set) var position: CGPoint
    var isMoving: Bool {!grounded || abs(velocity.dx) >= 45}

    init(position: CGPoint, velocity: CGVector, area: CGRect, size: CGFloat, time: TimeInterval) {
        bounds = CGRect(x:area.minX,y:area.minY,width:max(0,area.width-size),height:max(0,area.height-size))
        self.position = CGPoint(x:max(bounds.minX,min(bounds.maxX,position.x)),y:max(bounds.minY,min(bounds.maxY,position.y)))
        self.velocity = CGVector(dx:bounds.width > 0 ? velocity.dx : 0,dy:bounds.height > 0 ? velocity.dy : 0)
        previousTime = time
        grounded = bounds.height == 0
    }

    mutating func advance(at time: TimeInterval) {
        let elapsed = min(time-previousTime,0.1)
        guard elapsed > 0 else {return}
        previousTime = time
        // 帧间隔较长时分步检测碰撞，避免穿过边缘。
        let steps = Int(ceil(elapsed*120))
        let step = elapsed/Double(steps)
        for _ in 0..<steps where isMoving {advanceStep(step)}
    }

    private mutating func advanceStep(_ step: TimeInterval) {
        let resistance = exp(-(grounded ? 4.2 : 0.85)*step)
        velocity.dx *= resistance
        if !grounded {velocity.dy = velocity.dy*resistance+1100*step}

        let x = position.x+velocity.dx*step, y = position.y+velocity.dy*step
        position.x = max(bounds.minX,min(bounds.maxX,x))
        position.y = max(bounds.minY,min(bounds.maxY,y))
        if x != position.x {velocity.dx *= -Self.restitution}
        if y < bounds.minY {velocity.dy *= -Self.restitution}
        else if !grounded && y >= bounds.maxY {
            if velocity.dy < 165 {grounded = true; velocity.dy = 0}
            else {velocity.dy *= -Self.restitution}
        }
    }
}
