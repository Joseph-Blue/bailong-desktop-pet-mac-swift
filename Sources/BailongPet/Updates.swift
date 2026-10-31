import AppKit

struct GitHubRelease: Decodable {
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
}

struct UpdateFailure: Error {
    let title: String
    let message: String
    let detail: String

    static func network(_ error: Error) -> Self {
        let error = error as NSError
        let detail = "错误域：\(error.domain)\n错误码：\(error.code)\n原始错误：\(error.localizedDescription)"
        guard error.domain == NSURLErrorDomain else {
            return Self(title:"更新检查未完成",message:"请重新检查，或前往 GitHub 发布页查看。",detail:detail)
        }
        let text: (String,String)
        switch URLError.Code(rawValue:error.code) {
        case .notConnectedToInternet:
            text = ("当前未连接互联网","请连接网络后重新检查。")
        case .timedOut:
            text = ("GitHub 更新检查超时","本次未能在规定时间内完成，请重试或打开发布页查看。")
        case .networkConnectionLost:
            text = ("更新信息接收中断","本次检查未完成，请重试。")
        case .cannotFindHost, .dnsLookupFailed:
            text = ("无法找到更新服务器","无法解析 GitHub 地址，请检查网络或代理设置。")
        case .cannotConnectToHost:
            text = ("无法连接 GitHub","本次未能连接更新服务。可重试或在浏览器中打开发布页。")
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            text = ("无法建立安全连接","无法通过更新服务器的安全连接验证。")
        case .cannotDecodeRawData, .cannotDecodeContentData, .cannotParseResponse, .badServerResponse:
            text = ("未能读取更新信息","收到的发布信息不完整或格式不正确。")
        default:
            text = ("更新检查未完成","请重新检查，或前往 GitHub 发布页查看。")
        }
        return Self(title:text.0,message:text.1,detail:detail)
    }
    static func http(_ response: HTTPURLResponse) -> Self {
        let code = response.statusCode
        let retry = response.value(forHTTPHeaderField:"Retry-After")
        let remaining = response.value(forHTTPHeaderField:"X-RateLimit-Remaining")
        let reset = response.value(forHTTPHeaderField:"X-RateLimit-Reset")
        var detail = "HTTP 状态：\(code)"
        for key in ["Retry-After","X-RateLimit-Remaining","X-RateLimit-Reset","X-GitHub-Request-Id"] {
            if let value = response.value(forHTTPHeaderField:key) {detail += "\n\(key)：\(value)"}
        }
        if code == 429 || (code == 403 && (remaining == "0" || retry != nil)) {
            var resume: Date?
            if let retry {
                if let seconds = Double(retry), seconds.isFinite, seconds >= 0 {
                    resume = Date().addingTimeInterval(seconds)
                } else {
                    let format = DateFormatter(); format.locale = Locale(identifier:"en_US_POSIX")
                    format.timeZone = TimeZone(secondsFromGMT:0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    resume = format.date(from:retry)
                }
            }
            if resume == nil, remaining == "0", let reset, let seconds = Double(reset), seconds.isFinite {
                resume = Date(timeIntervalSince1970:seconds)
            }
            let message = resume.map {"可在 " + DateFormatter.localizedString(from:$0,dateStyle:.short,timeStyle:.medium) + " 后重新检查。"} ?? "请稍后重新检查。"
            return Self(title:"检查次数已达上限",message:message,detail:detail)
        }
        switch code {
        case 401,403: return Self(title:"更新请求被拒绝",message:"GitHub 未接受这次请求，请稍后重试。",detail:detail)
        case 404: return Self(title:"未找到正式发布",message:"可打开 GitHub 发布页查看版本。",detail:detail)
        case 407: return Self(title:"代理需要认证",message:"请完成代理认证后重新检查。",detail:detail)
        case 500...599: return Self(title:"更新服务响应异常",message:"请稍后重试，或直接查看 GitHub 发布页。",detail:detail)
        default: return Self(title:"更新检查未完成",message:"请重新检查，或前往 GitHub 发布页查看。",detail:detail)
        }
    }
    static func unreadable(_ detail: String) -> Self {
        Self(title:"未能读取更新信息",message:"收到的发布信息不完整或格式不正确。",detail:detail)
    }
}

/// All observable state is owned by the main queue. Network decoding runs off-main.
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()
    static let didChange = Notification.Name("BailongUpdateCheckChanged")
    static let repository = URL(string:"https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift")!
    static let releases = repository.appendingPathComponent("releases")
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var generation = 0
    private var automatic = false
    private var slowTimer: Timer?
    private(set) var slow = false
    private(set) var failure: UpdateFailure?
    private(set) var checking = false
    private(set) var release: GitHubRelease?
    private(set) var releaseURL: URL?
    private(set) var status: String
    var headline: String {checking && slow ? "连接 GitHub 较慢" : status}
    var explanation: String {
        if checking && slow {return "仍在等待更新信息，你可以继续等待或取消检查。"}
        return failure?.message ?? ""
    }
    var recordText: String {failure == nil ? status : "检查未完成 · " + status}
    var technicalDetails: String {
        guard let failure else {return ""}
        return "当前版本：\(Paths.version)\n检查地址：https://api.github.com/repos/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/latest\n检查时间：\(lastCheckText)\n\(failure.detail)"
    }
    var lastCheck: Date? {UserDefaults.standard.object(forKey:"updateLastCheck") as? Date}
    var lastCheckText: String {
        guard let date = lastCheck else {return "尚未检查"}
        return DateFormatter.localizedString(from:date,dateStyle:.medium,timeStyle:.medium)
    }
    override private init() {
        status = UserDefaults.standard.string(forKey:"updateLastResult") ?? "尚未检查"
        super.init()
        NotificationCenter.default.addObserver(self,selector:#selector(preferencesChanged),name:PetPreferences.didChange,object:nil)
    }
    @objc private func preferencesChanged() {
        if automatic && checking && !PetPreferences.shared.bool("automaticallyCheckUpdates") {cancel()}
    }
    private func notify() {NotificationCenter.default.post(name:Self.didChange,object:self)}
    func check(automatically: Bool = false) {
        if checking {
            // A manual request adopts the in-flight startup check without issuing a second request.
            if !automatically {automatic = false; notify()}
            return
        }
        generation += 1; let requestGeneration = generation
        automatic = automatically; checking = true; release = nil; releaseURL = nil
        failure = nil; slow = false
        status = "正在检查更新…"; notify()
        let timer = Timer(timeInterval:8,repeats:false) { [weak self] _ in
            guard let self, self.checking, self.generation == requestGeneration else {return}
            self.slow = true; self.slowTimer = nil; self.notify()
        }
        slowTimer = timer; RunLoop.main.add(timer,forMode:.common)
        // Leave proxy settings untouched: URLSession uses macOS system proxies, and TUN uses system routing.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration:configuration); self.session = session
        var request = URLRequest(url:URL(string:"https://api.github.com/repos/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/latest")!)
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("2026-03-10",forHTTPHeaderField:"X-GitHub-Api-Version")
        request.setValue("BailongPet/"+Paths.version,forHTTPHeaderField:"User-Agent")
        task = session.dataTask(with:request) { [weak self] data,response,error in
            let result: Result<GitHubRelease,Error> = Result {
                if let error {throw error}
                guard let response = response as? HTTPURLResponse else {throw UpdateFailure.unreadable("未收到 HTTP 响应。")}
                guard response.statusCode == 200 else {throw UpdateFailure.http(response)}
                guard let data, !data.isEmpty else {throw UpdateFailure.unreadable("HTTP 200，响应正文为空。")}
                let release: GitHubRelease
                do {release = try JSONDecoder().decode(GitHubRelease.self,from:data)}
                catch {throw UpdateFailure.unreadable("HTTP 200，JSON 解析失败：\(error.localizedDescription)")}
                guard !release.draft, !release.prerelease else {throw UpdateFailure(title:"未获取到正式版本",message:"本应用只检查正式发布，可前往 GitHub 查看其他版本。",detail:"发布标签：\(release.tag_name)\ndraft：\(release.draft)，prerelease：\(release.prerelease)")}
                guard let version = SemanticVersion.releaseTag(release.tag_name), version.prerelease.isEmpty else {
                    throw UpdateFailure(title:"无法识别新版本号",message:"请前往 GitHub 发布页查看版本说明。",detail:"发布标签：\(release.tag_name)")
                }
                return release
            }
            DispatchQueue.main.async {
                guard let self, self.generation == requestGeneration else {return}
                self.complete(result)
            }
        }
        task?.resume()
    }
    private func complete(_ result: Result<GitHubRelease,Error>) {
        checking = false; slow = false; slowTimer?.invalidate(); slowTimer = nil
        task = nil; session?.finishTasksAndInvalidate(); session = nil
        if case .failure(let error) = result, (error as NSError).domain == NSURLErrorDomain,
           (error as NSError).code == URLError.cancelled.rawValue {
            automatic = false; status = "已取消检查"; notify(); return
        }
        var newer = false
        switch result {
        case .success(let release):
            self.release = release
            releaseURL = Self.repository.appendingPathComponent("releases/tag").appendingPathComponent(release.tag_name)
            if let local = SemanticVersion(Paths.version), let remote = SemanticVersion.releaseTag(release.tag_name) {
                newer = local < remote
                status = newer ? "发现新版本：\(release.tag_name)" : local == remote ? "已是最新正式版本" : "本地版本领先于最新正式发布"
            } else {
                failure = UpdateFailure(title:"无法比较版本",message:"当前应用的版本号无法识别，请手动查看发布页。",detail:"当前版本：\(Paths.version)")
                self.release = nil
                status = failure!.title
            }
        case .failure(let error):
            failure = (error as? UpdateFailure) ?? UpdateFailure.network(error)
            status = failure!.title
        }
        UserDefaults.standard.set(Date(),forKey:"updateLastCheck")
        UserDefaults.standard.set(recordText,forKey:"updateLastResult")
        let shouldNotify = automatic && newer && PetPreferences.shared.bool("automaticallyCheckUpdates")
        automatic = false; notify()
        // Failed startup checks are recorded in Settings, never presented as alerts.
        if shouldNotify {UpdateWindow.show(check:false,activate:false,automaticallyPresented:true)}
    }
    func cancel() {
        guard checking else {return}
        generation += 1; task?.cancel(); task = nil; session?.invalidateAndCancel(); session = nil
        checking = false; automatic = false; slow = false; slowTimer?.invalidate(); slowTimer = nil
        status = "已取消检查"; notify()
    }
}

final class UpdateWindow: NSObject, NSWindowDelegate {
    private static var current: UpdateWindow?
    private let window = NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:400),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
    private let status = NSTextField(wrappingLabelWithString:"")
    private let explanation = NSTextField(wrappingLabelWithString:"")
    private let versions = NSTextField(labelWithString:"")
    private let timestamp = NSTextField(labelWithString:"")
    private let notes = NSTextView(frame:NSRect(x:0,y:0,width:540,height:220))
    private let notesScroll = NSScrollView()
    private var notesHeight: NSLayoutConstraint!
    private let details = NSTextView(frame:NSRect(x:0,y:0,width:540,height:110))
    private let detailsScroll = NSScrollView()
    private var detailsHeight: NSLayoutConstraint!
    private let detailsRow = NSStackView()
    private let disclosure = ActionButton("▸ 技术详情") {}
    private let copyDetails = ActionButton("拷贝详情") {}
    private var detailsExpanded = false
    private let spinner = NSProgressIndicator()
    private let retry = ActionButton("重新检查") {UpdateChecker.shared.check()}
    private let download = ActionButton("打开 GitHub 发布页") {}
    private let close = ActionButton("关闭") {}
    private let disableAutomatic = ActionButton("😡 不许打扰我，禁用自动更新检查") {}
    private let buttons = NSStackView()
    private let spacer = NSView()
    private var failedLayout: Bool?
    private var automaticPresentation = false
    private var automaticWindowWidth: CGFloat = 580
    static func show(check: Bool = true, activate: Bool = true, automaticallyPresented: Bool = false) {
        if current == nil {current = UpdateWindow()}
        guard let current else {return}
        current.automaticPresentation = automaticallyPresented
        if check {UpdateChecker.shared.check()}
        current.refresh()
        if activate {NSApp.activate(ignoringOtherApps:true); current.window.makeKeyAndOrderFront(nil)}
        else {current.window.orderFront(nil)}
    }
    override private init() {
        super.init()
        window.title = "检查更新"; window.isReleasedWhenClosed = false; window.delegate = self
        window.collectionBehavior = [.fullScreenNone]; window.standardWindowButton(.zoomButton)?.isEnabled = false
        let root = NSView(); window.contentView = root
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        status.font = .systemFont(ofSize:18,weight:.semibold)
        explanation.font = .systemFont(ofSize:13); explanation.textColor = .secondaryLabelColor
        versions.font = .systemFont(ofSize:12); timestamp.font = .systemFont(ofSize:11); timestamp.textColor = .secondaryLabelColor
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let heading = NSStackView(views:[spinner,status]); heading.spacing = 8
        for (scroll,text) in [(notesScroll,notes),(detailsScroll,details)] {
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
            text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
            text.minSize = .zero; text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.textContainer?.containerSize = NSSize(width:540,height:CGFloat.greatestFiniteMagnitude)
            text.textContainerInset = NSSize(width:4,height:4); scroll.documentView = text
        }
        details.font = .monospacedSystemFont(ofSize:11,weight:.regular)
        detailsRow.spacing = 10
        for view in [disclosure,NSView(),copyDetails] {detailsRow.addArrangedSubview(view)}
        disclosure.callback = { [weak self] in guard let self else {return}; self.detailsExpanded.toggle(); self.refresh() }
        copyDetails.callback = {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(UpdateChecker.shared.technicalDetails,forType:.string)
        }
        close.callback = { [weak self] in self?.window.performClose(nil) }
        download.callback = {
            let url = UpdateChecker.shared.releaseURL ?? UpdateChecker.releases
            if !NSWorkspace.shared.open(url) {showError("无法打开发布页",PetFailure(message:url.absoluteString))}
        }
        disableAutomatic.callback = { [weak self] in
            PetPreferences.shared.set(false,for:"automaticallyCheckUpdates")
            self?.window.performClose(nil)
        }
        buttons.spacing = 10
        automaticWindowWidth = max(580,[retry,disableAutomatic,close,download].reduce(CGFloat(80)) {$0 + $1.fittingSize.width})
        for view in [heading,explanation,versions,timestamp,notesScroll,detailsRow,detailsScroll,buttons] {stack.addArrangedSubview(view)}
        root.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:20), stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-20),
            stack.topAnchor.constraint(equalTo:root.topAnchor,constant:20), stack.bottomAnchor.constraint(equalTo:root.bottomAnchor,constant:-16)
        ])
        for view in [heading,explanation,notesScroll,detailsRow,detailsScroll,buttons] {
            view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        }
        notesHeight = notesScroll.heightAnchor.constraint(equalToConstant:220)
        detailsHeight = detailsScroll.heightAnchor.constraint(equalToConstant:110)
        NotificationCenter.default.addObserver(self,selector:#selector(refresh),name:UpdateChecker.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAutomaticOption),name:PetPreferences.didChange,object:nil)
        window.center()
    }
    @objc private func refreshAutomaticOption() {
        disableAutomatic.isEnabled = PetPreferences.shared.bool("automaticallyCheckUpdates")
    }
    @objc private func refresh() {
        let checker = UpdateChecker.shared, failed = checker.failure != nil
        if failedLayout != failed {
            for view in buttons.arrangedSubviews {buttons.removeArrangedSubview(view); view.removeFromSuperview()}
            let views = failed ? [spacer,close,download,retry] : [retry,disableAutomatic,spacer,close,download]
            for view in views {buttons.addArrangedSubview(view)}
            failedLayout = failed; detailsExpanded = false
        }
        disableAutomatic.isHidden = !automaticPresentation
        refreshAutomaticOption()
        let width = automaticPresentation && !failed ? automaticWindowWidth : 580
        status.stringValue = checker.headline
        explanation.stringValue = checker.explanation; explanation.isHidden = checker.explanation.isEmpty
        let hasNotes = checker.release != nil && !failed
        notesHeight.isActive = hasNotes; notesScroll.isHidden = !hasNotes
        detailsRow.isHidden = !failed
        let showDetails = failed && detailsExpanded
        detailsHeight.isActive = showDetails; detailsScroll.isHidden = !showDetails
        copyDetails.isHidden = !showDetails
        disclosure.title = detailsExpanded ? "▾ 技术详情" : "▸ 技术详情"
        details.string = checker.technicalDetails
        let headingHeight = (checker.headline as NSString).boundingRect(with:NSSize(width:width-70,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:status.font!]).height
        let messageHeight = checker.explanation.isEmpty ? 0 : max(18,(checker.explanation as NSString).boundingRect(with:NSSize(width:width-40,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:explanation.font!]).height.rounded(.up))+12
        let height = max(24,headingHeight.rounded(.up)) + 136 + messageHeight + (hasNotes ? 232 : 0) + (failed ? 40 : 0) + (showDetails ? 122 : 0)
        let top = window.frame.maxY
        window.setContentSize(NSSize(width:width,height:height))
        window.setFrameOrigin(NSPoint(x:window.frame.minX,y:top-window.frame.height))
        versions.stringValue = "当前版本 \(Paths.version)" + (hasNotes ? " · 最新正式发布 \(checker.release!.tag_name)" : "")
        timestamp.stringValue = "上次检查时间：" + checker.lastCheckText
        retry.title = failed ? "重试" : "重新检查"; retry.isEnabled = !checker.checking; retry.emphasize(failed)
        download.title = failed ? "查看发布页" : "打开 GitHub 发布页"; download.emphasize(!failed)
        close.title = checker.checking ? "取消检查" : "关闭"
        if checker.checking {spinner.startAnimation(nil)} else {spinner.stopAnimation(nil)}
        let body = checker.release?.body?.trimmingCharacters(in:.whitespacesAndNewlines)
        notes.textStorage?.setAttributedString(MarkdownText.render(body?.isEmpty == false ? body! : checker.release == nil ? "" : "此版本未提供更新说明。",font:.systemFont(ofSize:13)))
    }
    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.current = nil; UpdateChecker.shared.cancel()
    }
}
