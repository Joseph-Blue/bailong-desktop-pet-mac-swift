import AppKit

enum MessageSettingsPage {
    static func render(form:SettingsForm,onPreview:@escaping (MessagePurpose) -> Void) {
        form.group("历史记录",[form.toggle("记录历史","recordHistory",detail:"关闭后保留已有记录，停止保存新内容；重新开启不会补录。Codex 自身的记录不受影响。")])
        form.group("气泡窗审批",[form.choice("气泡窗审批按钮顺序","approvalButtonOrder",[("rejectLeft","左拒绝 · 右允许"),("allowLeft","左允许 · 右拒绝")],detail:"只调整气泡中的按钮位置。红叉拒绝、绿对钩允许；审批需点击按钮，不能用键盘提交。")])
        form.group("输入快捷键",[form.choice("发送与换行","sendShortcut",SendShortcut.options)])
        form.group("任务气泡",[
            form.toggle("显示任务气泡","taskBubbles",detail:"关闭后仍会显示审批、待回答的问题和错误提示。"),
            form.toggle("任务消息","progressBubbles",requires:["taskBubbles"]),
            form.toggle("最终回复","resultBubbles",requires:["taskBubbles"]),
            form.toggle("思考与工具进展小气泡","progressToastEnabled",requires:["taskBubbles","progressBubbles"])])
        form.group("进展提醒",[
            form.toggle("久无进展时提醒","taskReminderEnabled",detail:"任务连续 90 秒没有新进展后，按下方间隔提醒。等待回答、批准或正在停止时不提醒。",requires:["taskBubbles","progressBubbles"]),
            form.slider("提醒间隔","taskReminderMinutes",range:1...30,suffix:"分钟",requires:["taskBubbles","progressBubbles","taskReminderEnabled"])])
        form.group("显示哪些消息",[
            form.toggle("互动台词","interactionBubbles"),
            form.toggle("显示思考摘要","showThinkingProgress"),
            form.toggle("显示工具调用","showToolProgress")])
        form.group("气泡卡片与任务概览",[
            form.slider("气泡卡片保留数量","bubbleCardLimit",range:5...100,suffix:"条"),
            form.toggle("互动气泡显示任务概览","showTaskOverview",detail:"鼠标操作设为“显示任务进度、播放随机动画”时，台词下方显示任务列表。点击任务可在 Codex 中打开。"),
            form.slider("近期结束任务数量","recentTaskCount",range:1...20,suffix:"条",detail:"每个会话只显示最近一次任务。",requires:["showTaskOverview"])])
        form.group("停留时间",[
            form.slider("互动台词","interactionSeconds",range:0...60,suffix:"秒",requires:["interactionBubbles"]),
            form.slider("任务消息","progressSeconds",range:0...60,suffix:"秒",requires:["taskBubbles","progressBubbles"]),
            form.slider("最终回复","resultSeconds",range:0...120,suffix:"秒",requires:["taskBubbles","resultBubbles"]),
            form.slider("额度信息","quotaSeconds",range:0...120,suffix:"秒"),
            form.note("0 秒表示手动关闭。审批、问题和错误提示不会自动关闭。"),
            form.toggle("长回复自动延长阅读时间","autoReadTime",detail:"最长 120 秒。",requires:["taskBubbles","resultBubbles"]),
            form.toggle("鼠标移入时暂停倒计时","pauseOnHover"),
            form.slider("思考与工具进展小气泡","progressToastSeconds",range:1...10,suffix:"秒",detail:"内容更新后重新计时。",requires:["taskBubbles","progressBubbles","progressToastEnabled"]),
            form.row("预览最终回复气泡",control:ActionButton("预览…") {onPreview(.result)})])
        form.group("声音",[form.toggle("播放音效","soundEnabled")])
        form.group("安静陪伴",[
            form.toggle("立即开启安静陪伴","quietCompanion",detail:"减少活动并停止自动移动，隐藏互动台词和进展气泡，关闭音效。最终回复和待处理通知照常显示。"),
            form.toggle("定时开启安静陪伴","quietSchedule",detail:"手动开启后会一直保持安静，关闭后恢复定时安排。"),
            form.time("开始时间","quietStart",requires:["quietSchedule"]),
            form.time("结束时间","quietEnd",requires:["quietSchedule"]),
            form.note("按本机时间执行，可跨天；开始和结束时间相同表示全天。")])
    }
}
