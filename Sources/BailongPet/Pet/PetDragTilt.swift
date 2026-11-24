import Foundation
import CoreGraphics

struct PetDragTilt {
    let padding: CGSize
    private let strength: CGFloat
    private let maximumAngle: CGFloat
    private let pivot: CGPoint
    private let lever: CGVector
    private var previousPosition: CGPoint
    private var previousTime: TimeInterval
    private var velocity = CGVector.zero
    private var lastMovement: (time:TimeInterval,velocity:CGVector)?
    private var recentAcceleration: (time:TimeInterval,value:CGFloat)?
    private var angularVelocity: CGFloat = 0
    private(set) var angle: CGFloat = 0
    private(set) var isMoving = true

    init(pivot: CGPoint, center: CGPoint, size: CGFloat, strength: CGFloat, position: CGPoint, time: TimeInterval) {
        self.pivot = pivot
        self.strength = strength
        maximumAngle = (.pi / 10) * strength
        lever = CGVector(dx:(center.x-pivot.x)/size,dy:(center.y-pivot.y)/size)
        // 分别按两轴的最大位移留白，并预留素材绘制偏移。
        let reachX = max(abs(pivot.x),abs(size-pivot.x)), reachY = max(abs(pivot.y),abs(size-pivot.y))
        let sine = sin(maximumAngle), cosineLoss = 1-cos(maximumAngle), artworkMargin = size*0.03
        padding = CGSize(width:ceil(reachX*cosineLoss+reachY*sine+artworkMargin),
                         height:ceil(reachY*cosineLoss+reachX*sine+artworkMargin))
        previousPosition = position
        previousTime = time - 1 / 60
    }

    var rotation: CGAffineTransform {
        CGAffineTransform(translationX:pivot.x,y:pivot.y)
            .rotated(by:angle).translatedBy(x:-pivot.x,y:-pivot.y)
    }

    mutating func wake(at time: TimeInterval) {
        guard !isMoving else {return}
        previousTime = max(previousTime,time - 1 / 60)
        isMoving = true
    }

    mutating func release(at position: CGPoint, time: TimeInterval) -> CGVector? {
        if isMoving {advance(to:position,at:time,dragging:true)}
        previousTime = time
        isMoving = angle != 0 || angularVelocity != 0

        guard let lastMovement, time-lastMovement.time <= 0.065,
              let recentAcceleration, time-recentAcceleration.time <= 0.11 else {return nil}
        let velocity = lastMovement.velocity, speed = hypot(velocity.dx,velocity.dy)
        guard speed >= 1050 else {return nil}
        let boost = min(650,(recentAcceleration.value-4800)*0.055)
        let launchSpeed = min(2400,(speed+boost)*(0.55+0.45*strength))
        return CGVector(dx:velocity.dx/speed*launchSpeed,dy:velocity.dy/speed*launchSpeed)
    }

    mutating func advance(to position: CGPoint, at time: TimeInterval, dragging: Bool) {
        let elapsed = time - previousTime
        guard elapsed > 0 else {return}
        var target: CGFloat = 0
        if dragging {
            let gain = 1 - exp(-elapsed / 0.045)
            let dx = ((position.x-previousPosition.x)/elapsed-velocity.dx) * gain
            let dy = ((position.y-previousPosition.y)/elapsed-velocity.dy) * gain
            velocity.dx += dx; velocity.dy += dy
            if position != previousPosition {sampleThrow(dx:dx,dy:dy,elapsed:elapsed,time:time)}

            // 向下坐标系中，重力和反向加速度对抓点产生转矩。
            let gravity = lever.dx * 0.42
            let inertia = (lever.dy*dx-lever.dx*dy) / (elapsed * 5600)
            target = limited((gravity+inertia)*strength)
        }
        previousPosition = position; previousTime = time

        advanceSpring(toward:target,elapsed:elapsed)

        if abs(angle-target) < 0.0015, abs(angularVelocity) < 0.025,
           !dragging || hypot(velocity.dx,velocity.dy) < 2 {
            angle = target; angularVelocity = 0; velocity = .zero; isMoving = false
        }
    }

    private mutating func sampleThrow(dx: CGFloat, dy: CGFloat, elapsed: TimeInterval, time: TimeInterval) {
        lastMovement = (time,velocity)
        let speed = hypot(velocity.dx,velocity.dy)
        guard speed > 0 else {return}
        // 用沿速度方向的加速度判断甩动，松手前减速和横向抖动不增加推力。
        let forward = (velocity.dx*dx+velocity.dy*dy)/(speed*elapsed)
        if forward >= 4800 {recentAcceleration = (time,forward)}
    }

    private mutating func advanceSpring(toward target: CGFloat, elapsed: TimeInterval) {
        // 欠阻尼弹簧在这一帧的解析解，保留角速度，按真实时间穿过平衡点。
        let frequency: CGFloat = 17, damping: CGFloat = 0.43
        let decay = frequency*damping, oscillation = frequency*sqrt(1-damping*damping)
        let offset = angle-target, impulse = (angularVelocity+decay*offset)/oscillation
        let phase = oscillation*elapsed, envelope = exp(-decay*elapsed)
        let sine = sin(phase), cosine = cos(phase)
        let displacement = offset*cosine+impulse*sine
        let next = target+envelope*displacement
        angle = limited(next)
        angularVelocity = angle == next ? envelope*(oscillation*(impulse*cosine-offset*sine)-decay*displacement) : 0
    }

    private func limited(_ angle: CGFloat) -> CGFloat {max(-maximumAngle,min(maximumAngle,angle))}
}
