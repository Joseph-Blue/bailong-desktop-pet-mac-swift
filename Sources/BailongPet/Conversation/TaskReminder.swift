import Foundation

// 只保留时刻，复用已有同步节拍，不持有正文或创建逐任务定时器。
struct TaskReminderClock {
    var lastProgress:TimeInterval
    var lastNotice:TimeInterval
    init(now:TimeInterval) {lastProgress = now; lastNotice = now}
    static func isDue(now:TimeInterval,lastProgress:TimeInterval,lastNotice:TimeInterval,interval:TimeInterval) -> Bool {
        now-lastProgress >= 90 && now-lastNotice >= interval
    }
    func isDue(now:TimeInterval,interval:TimeInterval) -> Bool {
        Self.isDue(now:now,lastProgress:lastProgress,lastNotice:lastNotice,interval:interval)
    }
}

extension ChatController {
    func checkTaskReminder(now:TimeInterval) {
        guard let (conversation,turn) = running,!cancelled,!closing else {return}
        guard ["running","inProgress"].contains(turn.status) else {
            reminderClock = TaskReminderClock(now:now); return
        }
        guard let clock = reminderClock,clock.isDue(now:now,interval:pet.preferences.number("taskReminderMinutes")*60) else {return}
        if showTaskReminder(conversation:conversation,start:turn.date,key:"own",activityKey:turn.key) {reminderClock?.lastNotice = now}
    }
    @discardableResult
    func showTaskReminder(conversation:Conversation,start:Date,key:String,activityKey:String? = nil) -> Bool {
        guard pet.preferences.bool("taskReminderEnabled"),pet.preferences.allows(.progress),
              !pet.hidden,!pet.quotaActive,!pet.bubble.kind.hasPrefix("quota"),
              pet.bubble.purpose != .attention,!ui.composerVisible else {return false}
        pet.say(pet.preferences.statusLine("taskProgressTemplate"),body:"已经有一会儿没有新进度，任务尚未报告完成。",kind:"task",thread:conversation.key,
                purpose:.progress,personalizeTitle:false,animateHeading:true,timing:.init(start:start,key:key,activityKey:activityKey),messageID:"progress-reminder")
        return true
    }
}
