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
    var detail:SettingsDetail?
    var itemID:String?
    var anchorTitle:String?
    var anchor:String {group+"/"+(anchorTitle ?? title)}
    var location:String {[section.title,detail?.title,detail?.title == group ? nil : group].compactMap {$0}.joined(separator:" › ")}

    // 索引只保存设置文案，不创建页面或触发预览、磁盘统计、登录项查询。
    static func all(catalog:Catalog?) -> [Self] {
        var entries = [Self]()
        func add(_ section:SettingsSection,_ group:String,_ titles:[String],_ keywords:String = "") {
            entries += titles.map {Self(section:section,group:group,title:$0,keywords:keywords)}
        }
        add(.general,"启动",["登录时启动","随 Codex 启动","记住上次位置"],"开机 自启动 跟随 召回")
        add(.general,"权限与系统设置",["访达自动化"],"权限 授权 Finder 文件链接 最小化 恢复 自动化 系统设置")
        add(.general,"权限与系统设置",["文件与文件夹"],"权限 授权 文稿 桌面 下载 隐私 文件访问 系统设置")
        add(.general,"权限与系统设置",["登录项与后台运行"],"权限 批准 开机 自启动 跟随 后台 系统设置")
        add(.general,"桌面",["全屏时自动隐藏"],"屏幕 多屏")
        add(.general,"桌面",["所在显示器"],"屏幕 多屏 固定 随拖动切换屏幕")
        add(.identity,"我们怎么称呼彼此",["你的名字","桌宠的名字","特定称呼"],"主人 昵称 用户名 变量")
        add(.identity,"见面时说",["问候语"],"台词 欢迎 动作 播放 预览")
        add(.identity,"工作中台词",["随机工作中台词抽取"],"点击 任务列表 任务概览 随机 抽取 工作中 台词 执行任务中")
        entries.append(.init(section:.identity,group:"工作中台词",title:IdentitySettingsPage.editWorkingLineTitle,keywords:"任务概览 随机台词",detail:.lines))
        entries.append(.init(section:.identity,group:SettingsDetail.lines.title,title:SettingsDetail.lines.title,detail:.lines))
        entries += IdentitySettingsPage.items(catalog:catalog).map {$0.searchEntry(in:.identity)}
        if catalog != nil {entries.append(.init(section:.activity,group:SettingsDetail.actions.title,title:SettingsDetail.actions.title,detail:.actions))}
        entries += ActivitySettingsPage.items(catalog:catalog).map {$0.searchEntry(in:.activity)}
        let actionNames = PetGestureSetting.actions.map(\.1).joined(separator:" ")
        for gesture in PetGestureSetting.all {
            let keywords = [gesture.keywords, gesture.help, actionNames].compactMap {$0}.joined(separator:" ")
            add(.activity,PetGestureSetting.group,[gesture.title],keywords)
        }
        add(.activity,"桌宠吸边",["屏幕左右边缘吸边","左右露出比例","顶部刘海吸边","从刘海露出比例"],"刘海 屏幕 左右 边缘 顶部 收进刘海 收纳 倒挂 探头 召回 内建屏幕 MacBook 露出比例 55%")
        add(.activity,"自主活动",["活跃程度","活动间隔","自主移动","活动范围","减少重复动作","整体播放速度"],"动画 频率 安静 适中 活泼 自定义 倍速 待机 吸边 任务 排除上一动作 随机互动 原地陪伴 小范围活动 整个屏幕")
        add(.activity,"任务动作",["收到任务时播放开场","完成任务时播放庆祝"],"动画")
        entries += MessageSettingsPage.Topic.allCases.map {Self(section:.messages,group:$0.rawValue,title:$0.rawValue,detail:.messages($0))}
        entries += MessageSettingsPage.searchEntries
        add(.appearance,"大小",["桌宠大小","气泡大小","消息文字大小"],"缩放 字号 字体")
        add(.appearance,"大小",["气泡自定义宽高比","宽 : 高"],"气泡形状 长宽比 宽高比 比例 宽度 高度 排版")
        add(.appearance,"主题",["外观模式","强调色","自定义"],"主题 颜色 浅色 深色 跟随系统 分段选择 蓝色 紫色 粉色 红色 橙色 黄色 绿色 石墨色")
        add(.appearance,"消息窗口",["消息窗口材质","液态玻璃跟随系统设定","玻璃不透明度","气泡效果"],"液态玻璃 普通材质 分段选择 玻璃 透明 磨砂 背景 预览")
        add(.advanced,"设置文件",["导出设置","导入设置"],"备份 恢复")
        add(.advanced,"桌宠对话默认工作区",["默认工作区","恢复内置工作区","清理内置工作区"],"人设 新对话 默认目录 文件夹 Workspace 选择 访达 Finder 废纸篓 清理默认工作区")
        add(.advanced,"本应用所占本机存储",["本应用所占本机数据","内置任务文件夹","磁盘缓存","清空本应用的本机数据","清空磁盘缓存","数据目录"],"存储 磁盘 空间 清理 删除 访达 Finder 默认任务文件夹 清空本机数据 清空数据 刷新")
        add(.developer,"动画",["画质","素材帧率上限","动画缓冲帧数","常用动作开头缓存","整段动画预加载"],"画质与性能 性能 分辨率 原画 较高 中 低 运行内存 RAM 720 512 384 256 FPS 满帧 自动分辨率 缓冲 卡顿 6帧 24 MiB 0.25秒")
        add(.developer,"动画效果改善",["动态效果"],"画质与性能 性能 气泡 动画 启动 退出 显示 隐藏 淡化 淡入 淡出 减少动态效果")
        add(.developer,"动画效果改善",["动作平滑过渡","孤立杂点清理"],"画质与性能 性能 淡化 淡入淡出 轮廓 边缘净化 透明 残留 动态效果")
        add(.developer,"动画效果改善",["轮廓阴影"],"画质与性能 性能 桌宠轮廓 桌宠 描边 外发光 阴影 投影 边缘")
        add(.developer,"额度查询",["额度查询缓存","缓存时长"],"画质与性能 性能 额度 ChatGPT 订阅 立即刷新 重置 倒计时 5小时 每周额度 缓存 有效期 秒 15 60 300 5分钟 刷新")
        add(.developer,"应用统计",["开启应用性能信息统计浮窗"],"画质与性能 性能 CPU GPU FPS 运行内存 RAM Swap 性能监视器 统计浮窗 本段动画等帧次数 缺帧 最长等待时间 拷贝完整诊断 剪贴板")
        add(.updates,"版本",["当前版本","检查正式版本","公开仓库"],"更新 下载 GitHub 发布")
        add(.updates,"自动检查",["启动时检查更新"],"自动 新版")
        add(.updates,"检查记录",["上次检查时间"],"更新 检查结果")
        let aboutKeywords = "开源致谢 来源 作者 图标 Lucide SF Symbols GitHub Codex OpenAI 技术栈 AppKit macOS UI skill"
        add(.about,"关于",["关于"],aboutKeywords)
        add(.about,"关于",["来源与致谢"],aboutKeywords+" Git 状态符号 bash-git-prompt Powerlevel10k")
        add(.about,"来源与致谢",[AboutPageController.thirdPartyNoticesTitle],"开源许可 许可证 英文原文 图标 Lucide ISC Primer Octicons MIT")
        for index in entries.indices {
            if entries[index].section == .appearance && entries[index].title == "消息窗口材质" {
                entries[index].keywords += " SDK 兼容构建 普通材质"
                entries[index].condition = PetPreferences.glassAvailabilityDescription
            } else if entries[index].title == "液态玻璃跟随系统设定" {
                entries[index].condition = PetPreferences.glassAvailable ? "选择液态玻璃材质后显示" : PetPreferences.glassAvailabilityDescription
            } else if entries[index].title == "玻璃不透明度" {
                entries[index].condition = PetPreferences.glassAvailable ? "选择液态玻璃材质并关闭跟随系统设定后显示" : PetPreferences.glassAvailabilityDescription
            } else if entries[index].section == .appearance && entries[index].title == "自定义" {
                entries[index].condition = "选择自定义强调色后显示"
            } else if entries[index].section == .appearance && entries[index].title == "宽 : 高" {
                entries[index].condition = "开启气泡自定义宽高比后显示"
            } else if entries[index].section == .developer && ["动画缓冲帧数","常用动作开头缓存"].contains(entries[index].title) {
                entries[index].condition = "关闭整段动画预加载后显示"
            } else if entries[index].section == .developer && entries[index].title == "动作平滑过渡" {
                entries[index].condition = "开启动态效果且系统未开启减少动态效果时生效"
            } else if entries[index].section == .developer && entries[index].title == "缓存时长" {
                entries[index].condition = "开启额度查询缓存后显示"
            } else if entries[index].section == .activity && entries[index].title == "左右露出比例" {
                entries[index].condition = "开启屏幕左右边缘吸边后可调整"
            } else if entries[index].section == .activity && entries[index].title == "从刘海露出比例" {
                entries[index].condition = "开启顶部刘海吸边后可调整"
            } else if entries[index].section == .activity && entries[index].title == "活动范围" {
                entries[index].condition = "开启自主移动后可调整"
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
        scroll.verticalScrollElasticity = .allowed
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
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int) -> NSTableRowView? {AccentSelectionRow()}
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
