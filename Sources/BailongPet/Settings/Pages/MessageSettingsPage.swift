import AppKit

enum MessageSettingsPage {
    static func render(form:SettingsForm,onPreview:@escaping (MessagePurpose) -> Void) {
        form.group("历史记录",[form.toggle("记录历史","recordHistory",detail:"关闭后停止新增和更新本机历史，已有记录保留。当前任务上下文暂留运行内存 (RAM)，重新开启不补写关闭期间的内容。Codex 原有记录不受此开关影响。")])
        form.group("气泡窗审批",[form.choice("气泡窗审批按钮顺序","approvalButtonOrder",[("rejectLeft","左拒绝 · 右允许"),("allowLeft","左允许 · 右拒绝")],detail:"仅改变桌宠气泡窗中的审批按钮位置，不改变原生审批对话框或 Codex 界面。红叉表示拒绝，绿对钩表示允许；键盘按键不触发审批。")])
        form.group("输入快捷键",[
            form.choice("发送与换行","sendShortcut",SendShortcut.options),
            form.note(SendShortcut.settingsExplanation)])
        form.group("显示哪些消息",[
            form.toggle("任务气泡提醒","taskBubbles"),form.toggle("任务进展","progressBubbles"),form.toggle("最终回复","resultBubbles"),form.toggle("互动台词","interactionBubbles"),
            form.toggle("显示思考过程","showThinkingProgress",detail:"在任务概览和进展小气泡中显示公开思考摘要，不计入气泡记录。"),
            form.toggle("显示工具调用","showToolProgress",detail:"在任务概览和进展小气泡中显示工具名称、操作和执行状态，不计入气泡记录。"),
            form.toggle("自动显示进展小气泡","progressToastEnabled",detail:"默认关闭。开启后，思考摘要或工具状态变化时自动弹出，优先放在桌宠上方；不打断审批、问卷和输入。"),
            form.note("需要处理的审批、补充输入与任务失败仍保留通知入口。关闭气泡不会停止任务或删除历史。")])
        form.group("气泡卡片与任务概览",[
            form.slider("气泡卡片保留数量","bubbleCardLimit",range:5...100,suffix:"条",detail:"默认 20 条，可设为 5～100 条，仅保留在本次运行的运行内存 (RAM) 中。普通对白不计入，任务概览只占一条；正在阅读和待处理卡片保留，不删除历史对话。"),
            form.toggle("互动气泡显示任务概览","showTaskOverview",detail:"通过按键执行“显示任务进度、播放随机动画”时，在台词下显示当前与近期结束任务；点击任务行跳转 Codex。"),
            form.slider("近期结束任务数量","recentTaskCount",range:1...20,suffix:"条",detail:"默认 5 条，每个会话显示最新轮次。任务概览关闭时保留此设置。")])
        form.group("停留时间",[
            form.slider("互动台词","interactionSeconds",range:0...60,suffix:"秒"),form.slider("任务进展","progressSeconds",range:0...60,suffix:"秒"),form.slider("最终回复","resultSeconds",range:0...120,suffix:"秒"),form.slider("额度信息","quotaSeconds",range:0...120,suffix:"秒"),form.note("设为 0 秒表示手动关闭。审批、补充输入和失败提示保留到处理或手动关闭。"),
            form.toggle("长回复自动延长阅读时间","autoReadTime",detail:"最多延长到 120 秒；手动关闭模式不受影响。"),form.toggle("鼠标移入时暂停倒计时","pauseOnHover"),form.toggle("文字显示完毕后开始计时","countAfterReveal",detail:"暂时停用。正文即时显示，计时从气泡出现开始。",enabled:false),
            form.slider("进展小气泡停留时间","progressToastSeconds",range:1...10,suffix:"秒",detail:"默认 2 秒，思考与工具调用共用；内容更新后重新计时，不占气泡记录。")])
        form.group("显示与声音",[form.toggle("逐步显示文字","typingEffect",detail:"正文打字机暂时停用；保留原设置。",enabled:false),form.toggle("播放音效","soundEnabled"),form.row("最终回复时长",control:ActionButton("预览…") {onPreview(.result)})])
        form.group("安静陪伴",[form.toggle("安静陪伴模式","quietCompanion",detail:"减少自主活动、停止自动移动，关闭互动台词、进展气泡和音效。最终回复与待处理通知保留。"),form.toggle("启用专注时段","quietSchedule"),form.time("开始时间","quietStart"),form.time("结束时间","quietEnd"),form.note("按本机时间生效，支持跨午夜；起止相同表示全天。")])
    }
}
