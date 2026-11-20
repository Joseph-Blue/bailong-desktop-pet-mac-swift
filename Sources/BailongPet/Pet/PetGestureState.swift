import Foundation

enum PetGesture: CaseIterable {
    case singleClick, doubleClick, rightDoubleClick, forceClick
}

// SpriteView 接收原生事件；这里记录一次按压已触发的行为，以及仍待松手或到期的动作。
struct PetGestureState {
    private enum Phase { case single, double, dockClick, dockDouble, forceClick, dragging }
    private struct Press {
        let start: CGPoint
        let petOrigin: CGPoint
        let fromDock: Bool
        var phase: Phase
    }
    enum Drag { case recall, move(to:CGPoint, began:Bool) }
    enum Release { case click(PetGesture), finishDrag, handled }
    enum Context { case menu, doubleClick, handled }

    private var press: Press?
    private(set) var recallDeadline: TimeInterval?
    var isPressed: Bool {press != nil}
    var isDragging: Bool {press?.phase == .dragging}
    var allowsMovement: Bool {!isPressed || isDragging}

    mutating func begin(at point:CGPoint, petOrigin:CGPoint, docked:Bool, clickCount:Int, now:TimeInterval) -> PetGesture? {
        contextPress = nil
        let phase: Phase
        if docked {
            phase = recallDeadline.map {now <= $0} == true ? .dockDouble : .dockClick
        } else {
            phase = clickCount > 1 && clickCount.isMultiple(of:2) ? .double : .single
        }
        cancelRecall()
        press = Press(start:point, petOrigin:petOrigin, fromDock:docked, phase:phase)
        return phase == .dockDouble ? .doubleClick : nil
    }

    mutating func forceClick() -> PetGesture? {
        switch press?.phase {
        case .single, .double, .dockClick:
            press?.phase = .forceClick
            return .forceClick
        default: return nil
        }
    }

    mutating func drag(to point:CGPoint) -> Drag? {
        guard let current = press, current.phase != .forceClick else {return nil}
        let dx = point.x - current.start.x, dy = current.start.y - point.y
        let began = current.phase != .dragging
        if began {
            guard abs(dx) + abs(dy) >= 8 else {return nil}
            press?.phase = .dragging
        }
        if current.fromDock {return began ? .recall : nil}
        return .move(to:CGPoint(x:current.petOrigin.x + dx, y:current.petOrigin.y + dy), began:began)
    }

    mutating func release(docked:Bool, now:TimeInterval) -> Release? {
        guard let current = press else {return nil}
        press = nil
        switch current.phase {
        case .single: return .click(.singleClick)
        case .double: return .click(.doubleClick)
        case .dragging: return current.fromDock ? .handled : .finishDrag
        case .dockClick:
            if docked {recallDeadline = now + 0.25}
            return .handled
        case .dockDouble, .forceClick: return .handled
        }
    }

    mutating func cancelRecall() {recallDeadline = nil}

    mutating func recallDue(at now:TimeInterval) -> Bool {
        guard let recallDeadline, now >= recallDeadline else {return false}
        cancelRecall()
        return true
    }

    private struct ContextPress {
        let button: Int
        let time: TimeInterval
        let deadline: TimeInterval
        let point: CGPoint
        var wasPressed = true

        func matches(button:Int, point:CGPoint, at now:TimeInterval) -> Bool {
            self.button == button && (time...deadline).contains(now) && hypot(point.x-self.point.x, point.y-self.point.y) <= 8
        }
    }
    private var contextPress: ContextPress?
    private var consumedContextPress: (button:Int, through:TimeInterval)?

    mutating func contextDown(button:Int, at point:CGPoint, time:TimeInterval, interval:TimeInterval) -> Context {
        cancelRecall()
        if let consumedContextPress, consumedContextPress.button == button, time <= consumedContextPress.through {
            return .handled
        }
        consumedContextPress = nil
        if contextPress?.matches(button:button, point:point, at:time) == true {
            contextPress = nil
            return .doubleClick
        }
        contextPress = ContextPress(button:button, time:time, deadline:time+interval, point:point)
        return .menu
    }

    // NSMenu 跟踪期间第二次按下可先被菜单消费，也可稍后作为 NSEvent 送回桌宠。
    mutating func sampleMenuButton(_ button:Int, pressed:Bool, control:Bool, at point:CGPoint, time:TimeInterval) -> Bool {
        guard let first = contextPress, first.button == button else {return false}
        contextPress?.wasPressed = pressed
        guard pressed, !first.wasPressed, button != 0 || control,
              first.matches(button:button, point:point, at:time) else {return false}
        contextPress = nil
        consumedContextPress = (button,time)
        return true
    }
}
