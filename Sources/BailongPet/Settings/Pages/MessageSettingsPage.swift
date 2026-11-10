import AppKit

enum MessageSettingsPage {
    static func render(form:SettingsForm,onPreview:@escaping (MessagePurpose) -> Void) {
        form.group("历史记录",[form.toggle("记录历史","recordHistory",detail:"关闭后停止新增和更新本机历史，已有记录保留。当前任务上下文暂留运行内存 (RAM)，重新开启不补写关闭期间的内容。Codex 原有记录不受此开关影响。")])
        form.group("气泡窗审批",[form.choice("气泡窗审批按钮顺序","approvalButtonOrder",[("rejectLeft","左拒绝 · 右允许"),("allowLeft","左允许 · 右拒绝")],detail:"仅改变桌宠气泡窗中的审批按钮位置，不改变原生审批对话框或 Codex 界面。红叉表示拒绝，绿对钩表示允许；键盘按键不触发审批。")])
        form.group("输入快捷键",[form.choice("发送与换行","sendShortcut",SendShortcut.options)])
        form.group("任务气泡",[
            form.toggle("显示任务气泡","taskBubbles",detail:"控制任务消息、最终回复和思考与工具进展小气泡。审批、补充输入和失败提示仍会显示。"),
            form.toggle("任务消息","progressBubbles",detail:"显示执行中的助手消息。",requires:["taskBubbles"]),
            form.toggle("最终回复","resultBubbles",requires:["taskBubbles"]),
            form.toggle("思考与工具进展小气泡","progressToastEnabled",detail:"任务消息开启时，思考摘要或工具状态变化会自动弹出短气泡。",requires:["taskBubbles","progressBubbles"])])
        form.group("进展提醒",[
            form.toggle("久无进展时提醒","taskReminderEnabled",detail:"连续 90 秒没有新进展，且距上次消息达到提醒间隔时显示。等待回答、批准或正在停止时不提醒。",requires:["taskBubbles","progressBubbles"]),
            form.slider("提醒间隔","taskReminderMinutes",range:1...30,suffix:"分钟",requires:["taskBubbles","progressBubbles","taskReminderEnabled"])])
        form.group("显示哪些消息",[
            form.toggle("互动台词","interactionBubbles"),
            form.toggle("显示思考摘要","showThinkingProgress",detail:"在任务概览和进展小气泡中显示公开思考摘要，不计入气泡记录。"),
            form.toggle("显示工具调用","showToolProgress",detail:"在任务概览和进展小气泡中显示工具名称、操作和执行状态，不计入气泡记录。")])
        form.group("气泡卡片与任务概览",[
            form.slider("气泡卡片保留数量","bubbleCardLimit",range:5...100,suffix:"条"),
            form.toggle("互动气泡显示任务概览","showTaskOverview",detail:"通过按键执行“显示任务进度、播放随机动画”时，在台词下显示当前与近期结束任务；点击任务行跳转 Codex。"),
            form.slider("近期结束任务数量","recentTaskCount",range:1...20,suffix:"条",detail:"每个会话显示最新轮次。",requires:["showTaskOverview"])])
        form.group("停留时间",[
            form.slider("互动台词","interactionSeconds",range:0...60,suffix:"秒",requires:["interactionBubbles"]),
            form.slider("任务消息","progressSeconds",range:0...60,suffix:"秒",requires:["taskBubbles","progressBubbles"]),
            form.slider("最终回复","resultSeconds",range:0...120,suffix:"秒",requires:["taskBubbles","resultBubbles"]),
            form.slider("额度信息","quotaSeconds",range:0...120,suffix:"秒"),
            form.note("设为 0 秒表示手动关闭。审批、补充输入和失败提示保留到处理或手动关闭。"),
            form.toggle("长回复自动延长阅读时间","autoReadTime",detail:"最多延长到 120 秒；手动关闭模式不受影响。",requires:["taskBubbles","resultBubbles"]),
            form.toggle("鼠标移入时暂停倒计时","pauseOnHover"),
            form.slider("思考与工具进展小气泡","progressToastSeconds",range:1...10,suffix:"秒",detail:"默认 2 秒，内容更新后重新计时。",requires:["taskBubbles","progressBubbles","progressToastEnabled"]),
            form.row("预览最终回复气泡",control:ActionButton("预览…") {onPreview(.result)})])
        form.group("声音",[form.toggle("播放音效","soundEnabled")])
        form.group("安静陪伴",[
            form.toggle("立即开启安静陪伴","quietCompanion",detail:"减少自主活动、停止自动移动，关闭互动台词、进展气泡和音效。最终回复与待处理通知保留。"),
            form.toggle("定时开启安静陪伴","quietSchedule",detail:"立即开启时始终保持安静；关闭立即开启后，按设定时段生效。"),
            form.time("开始时间","quietStart",requires:["quietSchedule"]),
            form.time("结束时间","quietEnd",requires:["quietSchedule"]),
            form.note("按本机时间生效，支持跨午夜；起止相同表示全天。")])
    }
}
