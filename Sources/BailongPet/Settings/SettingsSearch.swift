import AppKit

final class SettingsWindow: NSWindow {
    private var restoredFrame:NSRect?
    func restoreSavedFrame(named name:String) -> Bool {
        // 保存标准尺寸作为绿灯恢复目标，再读取用户保存的窗口位置与尺寸。
        restoredFrame = frame
        let restored = setFrameUsingName(name)
        setFrameAutosaveName(name)
        return restored
    }
    override func zoom(_ sender:Any?) {
        guard let area = screen?.visibleFrame else {return}
        if frame.equalTo(area),let restoredFrame {setFrame(restoredFrame,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion); self.restoredFrame = nil}
        else {restoredFrame = frame; setFrame(area,display:true,animate:!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)}
    }
    var focusSearch: () -> Void = {}
    override func performKeyEquivalent(with event:NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command,.shift,.option,.control]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "f" {focusSearch(); return true}
        return super.performKeyEquivalent(with:event)
    }
}

struct SettingsSearchEntry {
    let section:SettingsSection
    let group:String
    let title:String
    var keywords = ""
    var condition = ""
    var anchor:String {group+"/"+title}
    var location:String {section.title+" › "+group}

    // 索引只保存设置文案，不创建页面或触发预览、磁盘统计、登录项查询。
    static func all(catalog:Catalog?) -> [Self] {
        var entries = [Self]()
        func add(_ section:SettingsSection,_ group:String,_ titles:[String],_ keywords:String = "") {
            entries += titles.map {Self(section:section,group:group,title:$0,keywords:keywords)}
        }
        add(.general,"启动",["登录时启动","随 Codex 启动","启动后显示桌宠","记住上次位置"],"开机 自启动 跟随 召回")
        add(.general,"权限与系统设置",["访达自动化"],"权限 授权 Finder 文件链接 最小化 恢复 自动化 系统设置")
        add(.general,"权限与系统设置",["文件与文件夹"],"权限 授权 文稿 桌面 下载 隐私 文件访问 系统设置")
        add(.general,"权限与系统设置",["登录项与后台运行"],"权限 批准 开机 自启动 跟随 后台 系统设置")
        add(.general,"桌面",["全屏时自动隐藏","所在显示器"],"屏幕 多屏")
        add(.identity,"我们怎么称呼彼此",["你的名字","桌宠的名字","特定称呼"],"主人 昵称 用户名 变量")
        add(.identity,"见面时说",["问候语"],"台词 欢迎 预览")
        add(.identity,"任务状态台词",["执行任务中","等待回答","等待批准","任务成功","任务失败","任务中断或取消"],"台词 审批 模板")
        add(.identity,"任务状态台词",["正在思考","正在调用工具","正在运行命令","已运行命令"],"台词 模板 思考摘要 工具调用 执行命令 运行命令 已运行命令 终端 进展小气泡")
        add(.identity,"额度查询台词",["正在查询"],"额度 台词")
        add(.activity,"鼠标互动",["单击桌宠","双击桌宠","右键双击桌宠"],"点击 临时聊天 查看额度 历史消息 显示任务进度 播放随机动画")
        add(.activity,"自主活动",["活跃程度","活动间隔","自主移动","活动范围","减少重复动作","整体播放速度"],"动画 频率 安静 活泼 倍速")
        add(.activity,"任务动作",["收到任务时播放开场","完成任务时播放庆祝"],"动画")
        add(.messages,"历史记录",["记录历史"],"聊天 保存 同步")
        add(.messages,"气泡窗审批",["气泡窗审批按钮顺序"],"批准 允许这一次 允许本轮 拒绝 左拒绝 右允许 左允许 右拒绝 左右 位置 红叉 绿对钩")
        add(.messages,"气泡卡片与任务概览",["气泡卡片保留数量","互动气泡显示任务概览","近期结束任务数量"],"消息 历史 上一条 下一条 正在执行 最近 完成")
        add(.messages,"显示哪些消息",["显示思考过程","显示工具调用"],"思考摘要 工具名称 操作 执行状态 短气泡 小窗口 顶部 进展 自动 弹出 开关")
        add(.messages,"显示哪些消息",["自动显示进展小气泡"],"默认关闭 思考摘要 工具调用 短气泡 小窗口 顶部 进展 自动 弹出 开关")
        add(.messages,"输入快捷键",["发送与换行"],"回车 Enter ⌃ Control Ctrl ⌘ Command ⇧ Shift ⌥ Option 备选1 备选2 默认 发送 换行 快捷回复 插话 问卷")
        add(.messages,"显示哪些消息",["任务气泡提醒","任务进展","最终回复","互动台词"],"通知 显示 开关")
        add(.messages,"停留时间",["互动台词","任务进展","最终回复","额度信息","长回复自动延长阅读时间","鼠标移入时暂停倒计时","文字显示完毕后开始计时"],"气泡 自动关闭 秒 时长 悬停")
        add(.messages,"停留时间",["进展小气泡停留时间"],"思考 工具调用 短气泡 小窗口 自动关闭 持续 时间 秒 时长 2s 2秒")
        add(.messages,"显示与声音",["逐步显示文字","播放音效","最终回复时长"],"打字机 声音 预览")
        add(.messages,"安静陪伴",["安静陪伴模式","启用专注时段","开始时间","结束时间"],"免打扰 时间 夜间 静音")
        add(.appearance,"大小",["桌宠大小","气泡大小","消息文字大小"],"缩放 字号 字体")
        add(.appearance,"气泡形状",["自定义宽高比","宽 : 高"],"气泡 长宽比 宽高比 比例 宽度 高度 形状 排版")
        add(.appearance,"主题",["外观模式","强调色","自定义"],"主题 颜色 浅色 深色 跟随系统")
        add(.appearance,"消息窗口",["消息窗口材质","液态玻璃跟随系统设定","玻璃不透明度","动态效果","气泡效果"],"玻璃 透明 磨砂 背景 动画 预览")
        add(.advanced,"设置文件",["导出设置","导入设置"],"备份 恢复")
        add(.advanced,"本应用所占本机存储",["本应用所占本机数据","默认任务文件夹","磁盘缓存","清空本应用的本机数据","清空磁盘缓存","数据目录"],"存储 磁盘 空间 清理 删除 访达 Finder 清空本机数据 清空数据")
        add(.developer,"动画",["画质","素材帧率上限","动画缓冲帧数","整段动画预加载"],"性能 内存 RAM 720 512 384 256 FPS 分辨率 缓冲")
        add(.developer,"应用统计",["开启应用性能信息统计浮窗"],"CPU GPU 内存 RAM Swap 性能监视器")
        add(.updates,"版本",["当前版本","检查正式版本","公开仓库"],"更新 下载 GitHub 发布")
        add(.updates,"自动检查",["启动时检查更新"],"自动 新版")
        add(.updates,"检查记录",["上次检查时间"],"更新 检查结果")
        add(.about,"关于",["关于","开源项目、技术栈与致谢"],"开源致谢 来源 作者 许可证 技术栈 AppKit macOS UI skill")
        for index in entries.indices {
            if ["液态玻璃跟随系统设定","玻璃不透明度"].contains(entries[index].title) {
                entries[index].condition = "选择液态玻璃材质后显示"
            } else if entries[index].section == .appearance && entries[index].title == "自定义" {
                entries[index].condition = "选择自定义强调色后显示"
            } else if entries[index].section == .appearance && entries[index].title == "宽 : 高" {
                entries[index].condition = "开启自定义宽高比后生效"
            }
        }
        if let catalog {
            add(.identity,"互动台词",(catalog.variants+catalog.work).filter {$0.line != nil}.map(\.title),"台词 模板")
            for (group,clips) in [("待机动作",catalog.idles+catalog.extras),("互动动作",catalog.variants),("工作动作",catalog.work),("移动动作",catalog.movementAnimations),("鼠标与额度动作",[catalog.dragAnimation,catalog.landingAnimation,catalog.quotaAnimation])] {
                add(.activity,group,clips.map(\.title),"动画 播放速度 倍速 频率 偏爱 预览")
            }
        }
        return entries
    }
    static func matching(_ query:String,in entries:[Self]) -> [Self] {
        let words = query.split(whereSeparator:{$0.isWhitespace}).map(String.init)
        guard !words.isEmpty else {return []}
        let matches = entries.filter {entry in
            let text = [entry.title,entry.location,entry.keywords].joined(separator:" ")
            return words.allSatisfy {text.localizedStandardContains($0)}
        }
        return matches.filter {$0.title.localizedStandardContains(query)} + matches.filter {!$0.title.localizedStandardContains(query)}
    }
}

private final class SettingsSearchTable: NSTableView {
    var open:() -> Void = {}
    var cancel:() -> Void = {}
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {open(); return}
        if event.keyCode == 53 {cancel(); return}
        super.keyDown(with:event)
    }
}

final class SettingsSearchResults: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = SettingsSearchTable()
    private let caption = NSTextField(labelWithString:"")
    private let empty = NSTextField(labelWithString:"没有找到设置项")
    private var entries = [SettingsSearchEntry]()
    var onOpen:(SettingsSearchEntry) -> Void = {_ in}
    var onCancel:() -> Void = {}
    init() {
        super.init(frame:.zero)
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        table.addTableColumn(NSTableColumn(identifier:.init("setting")))
        table.headerView = nil; table.style = .plain; table.backgroundColor = .clear; table.rowHeight = 62
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.autoresizingMask = [.width]
        table.intercellSpacing = .zero; table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(openSelection)
        table.setAccessibilityLabel("设置搜索结果")
        table.open = { [weak self] in self?.openSelection() }; table.cancel = { [weak self] in self?.onCancel() }
        scroll.documentView = table
        caption.font = .systemFont(ofSize:12,weight:.medium); caption.textColor = .secondaryLabelColor
        empty.font = .systemFont(ofSize:14); empty.textColor = .secondaryLabelColor
        for view in [caption,scroll,empty] {view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)}
        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo:leadingAnchor,constant:24),caption.topAnchor.constraint(equalTo:topAnchor,constant:20),
            scroll.topAnchor.constraint(equalTo:caption.bottomAnchor,constant:12),scroll.leadingAnchor.constraint(equalTo:leadingAnchor,constant:12),scroll.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),scroll.bottomAnchor.constraint(equalTo:bottomAnchor),
            empty.centerXAnchor.constraint(equalTo:centerXAnchor),empty.topAnchor.constraint(equalTo:caption.bottomAnchor,constant:40)
        ])
    }
    required init?(coder:NSCoder) {fatalError()}
    func show(_ values:[SettingsSearchEntry]) {
        entries = values; caption.stringValue = "\(values.count) 项结果"; empty.isHidden = !values.isEmpty
        table.reloadData()
        if !values.isEmpty {table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false); table.scrollRowToVisible(0)}
    }
    func focus() {window?.makeFirstResponder(table)}
    @objc func openSelection() {
        guard entries.indices.contains(table.selectedRow) else {return}
        onOpen(entries[table.selectedRow])
    }
    func numberOfRows(in tableView:NSTableView) -> Int {entries.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int) -> NSView? {
        let entry = entries[row], cell = NSTableCellView()
        let title = NSTextField(labelWithString:entry.title)
        title.font = .systemFont(ofSize:13,weight:.medium)
        let path = NSTextField(labelWithString:entry.location+(entry.condition.isEmpty ? "" : " · "+entry.condition))
        path.font = .systemFont(ofSize:11); path.textColor = .secondaryLabelColor
        for field in [title,path] {field.lineBreakMode = .byTruncatingTail}
        let arrow = NSImageView(image:NSImage(systemSymbolName:"chevron.right",accessibilityDescription:nil)!)
        arrow.contentTintColor = .tertiaryLabelColor
        for view in [title,path,arrow] {view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view)}
        cell.hoverHelp = entry.title+"\n"+path.stringValue
        cell.textField = title; cell.setAccessibilityLabel(entry.title+"，"+path.stringValue)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:12),title.topAnchor.constraint(equalTo:cell.topAnchor,constant:11),
            path.leadingAnchor.constraint(equalTo:title.leadingAnchor),path.topAnchor.constraint(equalTo:title.bottomAnchor,constant:5),
            arrow.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-12),arrow.centerYAnchor.constraint(equalTo:cell.centerYAnchor),arrow.widthAnchor.constraint(equalToConstant:12),
            title.trailingAnchor.constraint(lessThanOrEqualTo:arrow.leadingAnchor,constant:-12),path.trailingAnchor.constraint(lessThanOrEqualTo:arrow.leadingAnchor,constant:-12)
        ])
        return cell
    }
}

final class SettingsSearchHighlight: NSView {
    override func hitTest(_ point:NSPoint) -> NSView? {nil}
    override func draw(_ dirtyRect:NSRect) {
        AppAccent.color.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect:bounds,xRadius:6,yRadius:6).fill()
    }
}
