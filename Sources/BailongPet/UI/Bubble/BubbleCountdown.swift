import Foundation

final class BubbleCountdown {
    private var timer:Timer?
    func start(_ seconds:Double,paused:@escaping () -> Bool,expired:@escaping () -> Void) {
        stop()
        guard seconds > 0 else {return}
        var remaining = seconds, previous = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            let now = ProcessInfo.processInfo.systemUptime, delta = now-previous; previous = now
            if paused() {return}
            remaining -= delta
            if remaining <= 0 {self?.stop(); expired()}
        }
        self.timer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    func stop() {timer?.invalidate(); timer = nil}
    deinit {stop()}
}
