import AppKit

struct GitHubRelease: Decodable {
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool

    var displayTag: String {
        for prefix in [L10n.text(.about,"updates.gitHubRelease.text"),L10n.text(.about,"updates.gitHubRelease.text.2")] where tag_name.hasPrefix(prefix + "v") {
            return "\(prefix) \(tag_name.dropFirst(prefix.count))"
        }
        return tag_name
    }
}

struct UpdateFailure: Error {
    let title: String
    let message: String
    let detail: String
    var retryAt: Date? = nil

    static func network(_ error: Error) -> Self {
        let error = error as NSError
        let detail = L10n.format(.about,"updates.network.text",String(describing:error.domain),String(describing:error.code),String(describing:error.localizedDescription))
        guard error.domain == NSURLErrorDomain else {
            return Self(title:L10n.text(.about,"updates.network.title"),message:L10n.text(.about,"updates.network.message"),detail:detail)
        }
        let text: (String,String)
        switch URLError.Code(rawValue:error.code) {
        case .notConnectedToInternet:
            text = (L10n.text(.about,"updates.network.text.2"),L10n.text(.about,"updates.network.text.3"))
        case .timedOut:
            text = (L10n.text(.about,"updates.network.text.4"),L10n.text(.about,"updates.network.text.5"))
        case .networkConnectionLost:
            text = (L10n.text(.about,"updates.network.text.6"),L10n.text(.about,"updates.network.text.7"))
        case .cannotFindHost, .dnsLookupFailed:
            text = (L10n.text(.about,"updates.network.text.8"),L10n.text(.about,"updates.network.text.9"))
        case .cannotConnectToHost:
            text = (L10n.text(.about,"updates.network.text.10"),L10n.text(.about,"updates.network.text.11"))
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired:
            text = (L10n.text(.about,"updates.network.text.12"),L10n.text(.about,"updates.network.text.13"))
        case .cannotDecodeRawData, .cannotDecodeContentData, .cannotParseResponse, .badServerResponse:
            text = (L10n.text(.about,"updates.network.text.14"),L10n.text(.about,"updates.network.text.15"))
        default:
            text = (L10n.text(.about,"updates.network.title"),L10n.text(.about,"updates.network.message"))
        }
        return Self(title:text.0,message:text.1,detail:detail)
    }
    static func http(_ response: HTTPURLResponse, body:Data?) -> Self {
        let code = response.statusCode
        let retry = response.value(forHTTPHeaderField:"Retry-After")
        let remaining = response.value(forHTTPHeaderField:"X-RateLimit-Remaining")
        let reset = response.value(forHTTPHeaderField:"X-RateLimit-Reset")
        var detail = L10n.format(.about,"updates.http.text",String(describing:code))
        for key in ["Retry-After","X-RateLimit-Remaining","X-RateLimit-Reset","X-GitHub-Request-Id"] {
            if let value = response.value(forHTTPHeaderField:key) {detail += "\n\(key)：\(value)"}
        }
        let secondaryLimit = code == 403 && body.flatMap {String(data:$0,encoding:.utf8)}?.localizedCaseInsensitiveContains("secondary rate limit") == true
        if code == 429 || secondaryLimit || (code == 403 && (remaining == "0" || retry != nil)) {
            let now = Date()
            var retryAt: Date?
            if let retry {
                if let seconds = Double(retry), seconds.isFinite, seconds >= 0 {
                    retryAt = now.addingTimeInterval(seconds)
                } else {
                    let format = DateFormatter(); format.locale = Locale(identifier:"en_US_POSIX")
                    format.timeZone = TimeZone(secondsFromGMT:0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    retryAt = format.date(from:retry)
                }
            }
            var resetAt: Date?
            if remaining == "0", let reset, let seconds = Double(reset), seconds.isFinite {
                resetAt = Date(timeIntervalSince1970:seconds)
            }
            let resume = [retryAt,resetAt].compactMap {$0}.filter {$0 > now}.max() ?? now.addingTimeInterval(60)
            return rateLimited(until:resume,detail:detail)
        }
        switch code {
        case 401,403: return Self(title:L10n.text(.about,"updates.http.title"),message:L10n.text(.about,"updates.http.message"),detail:detail)
        case 404: return Self(title:L10n.text(.about,"updates.http.title.2"),message:L10n.text(.about,"updates.http.message.2"),detail:detail)
        case 407: return Self(title:L10n.text(.about,"updates.http.title.3"),message:L10n.text(.about,"updates.http.message.3"),detail:detail)
        case 500...599: return Self(title:L10n.text(.about,"updates.http.title.4"),message:L10n.text(.about,"updates.http.message.4"),detail:detail)
        default: return Self(title:L10n.text(.about,"updates.network.title"),message:L10n.text(.about,"updates.network.message"),detail:detail)
        }
    }
    static func rateLimited(until date:Date,detail:String? = nil) -> Self {
        let time = DateFormatter.localizedString(from:date,dateStyle:.short,timeStyle:.medium)
        return Self(title:L10n.text(.about,"updates.rateLimited.title"),message:L10n.format(.about,"updates.rateLimited.message",String(describing:time)),detail:detail ?? L10n.format(.about,"updates.rateLimited.text",String(describing:time)),retryAt:date)
    }
    static func unreadable(_ detail: String) -> Self {
        Self(title:L10n.text(.about,"updates.network.text.14"),message:L10n.text(.about,"updates.network.text.15"),detail:detail)
    }
}

/// All observable state is owned by the main queue. Network decoding runs off-main.
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()
    static let didChange = Notification.Name("BailongUpdateCheckChanged")
    static let repository = URL(string:"https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift")!
    static let releases = repository.appendingPathComponent("releases")
    private static let lastAttemptKey = "updateLastAttempt"
    private static let retryAtKey = "updateRetryAt"
    private static let automaticInterval: TimeInterval = 24 * 60 * 60
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
    var headline: String {checking && slow ? L10n.text(.about,"updates.updateChecker.text") : status}
    var explanation: String {
        if checking && slow {return L10n.text(.about,"updates.updateChecker.text.2")}
        return failure?.message ?? ""
    }
    var recordText: String {failure == nil ? status : L10n.text(.about,"updates.updateChecker.text.3") + status}
    var technicalDetails: String {
        guard let failure else {return ""}
        return L10n.format(.about,"updates.updateChecker.text.4",String(describing:Paths.version),String(describing:lastCheckText),String(describing:failure.detail))
    }
    var lastCheck: Date? {UserDefaults.standard.object(forKey:"updateLastCheck") as? Date}
    var lastCheckText: String {
        guard let date = lastCheck else {return L10n.text(.about,"updates.updateChecker.text.5")}
        return DateFormatter.localizedString(from:date,dateStyle:.medium,timeStyle:.medium)
    }
    override private init() {
        status = UserDefaults.standard.string(forKey:"updateLastResult") ?? L10n.text(.about,"updates.updateChecker.text.5")
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
        let defaults = UserDefaults.standard, now = Date()
        if let retryAt = defaults.object(forKey:Self.retryAtKey) as? Date, now < retryAt {
            if !automatically {
                if failure?.retryAt != retryAt {failure = .rateLimited(until:retryAt)}
                status = failure!.title
                notify()
            }
            return
        }
        if automatically, let lastAttempt = defaults.object(forKey:Self.lastAttemptKey) as? Date,
           now.timeIntervalSince(lastAttempt) < Self.automaticInterval {return}
        // Record the attempt before starting the request so cancellation and relaunch count too.
        defaults.set(now,forKey:Self.lastAttemptKey)
        defaults.removeObject(forKey:Self.retryAtKey)
        generation += 1; let requestGeneration = generation
        automatic = automatically; checking = true; release = nil; releaseURL = nil
        failure = nil; slow = false
        status = L10n.text(.about,"updates.check.text"); notify()
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
                guard let response = response as? HTTPURLResponse else {throw UpdateFailure.unreadable(L10n.text(.about,"updates.check.text.2"))}
                guard response.statusCode == 200 else {throw UpdateFailure.http(response,body:data)}
                guard let data, !data.isEmpty else {throw UpdateFailure.unreadable(L10n.text(.about,"updates.check.text.3"))}
                let release: GitHubRelease
                do {release = try JSONDecoder().decode(GitHubRelease.self,from:data)}
                catch {throw UpdateFailure.unreadable(L10n.format(.about,"updates.check.text.4",String(describing:error.localizedDescription)))}
                guard !release.draft, !release.prerelease else {throw UpdateFailure(title:L10n.text(.about,"updates.check.title"),message:L10n.text(.about,"updates.check.message"),detail:L10n.format(.about,"updates.check.error",String(describing:release.tag_name),String(describing:release.draft),String(describing:release.prerelease)))}
                guard let version = SemanticVersion.releaseTag(release.tag_name), version.prerelease.isEmpty else {
                    throw UpdateFailure(title:L10n.text(.about,"updates.check.title.2"),message:L10n.text(.about,"updates.check.message.2"),detail:L10n.format(.about,"updates.check.error.2",String(describing:release.tag_name)))
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
            automatic = false; status = L10n.text(.about,"updates.complete.text"); notify(); return
        }
        var newer = false
        switch result {
        case .success(let release):
            self.release = release
            releaseURL = Self.repository.appendingPathComponent("releases/tag").appendingPathComponent(release.tag_name)
            if let local = SemanticVersion(Paths.version), let remote = SemanticVersion.releaseTag(release.tag_name) {
                newer = local < remote
                status = newer ? L10n.format(.about,"updates.complete.text.2",String(describing:release.displayTag)) : local == remote ? L10n.text(.about,"updates.complete.text.3") : L10n.text(.about,"updates.complete.text.4")
            } else {
                failure = UpdateFailure(title:L10n.text(.about,"updates.complete.title"),message:L10n.text(.about,"updates.complete.message"),detail:L10n.format(.about,"updates.complete.error",String(describing:Paths.version)))
                self.release = nil
                status = failure!.title
            }
        case .failure(let error):
            failure = (error as? UpdateFailure) ?? UpdateFailure.network(error)
            if let retryAt = failure?.retryAt {UserDefaults.standard.set(retryAt,forKey:Self.retryAtKey)}
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
        status = L10n.text(.about,"updates.complete.text"); notify()
    }
}

final class UpdateWindow: NSObject, NSWindowDelegate {
    private static var current:UpdateWindow?
    private let window = NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:360),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
    private let stack = NSStackView()
    private let status = NSTextField(wrappingLabelWithString:"")
    private let explanation = NSTextField(wrappingLabelWithString:"")
    private let versions = NSTextField(wrappingLabelWithString:"")
    private let timestamp = NSTextField(labelWithString:"")
    private let heading = NSStackView()
    private let spinner = NSProgressIndicator()
    private let notes = AppTextView(frame:NSRect(x:0,y:0,width:552,height:220))
    private let notesScroll = GutterScrollView()
    private let notesSection = NSStackView()
    private let details = AppTextView(frame:NSRect(x:0,y:0,width:552,height:110))
    private let detailsScroll = GutterScrollView()
    private let detailsSection = NSStackView()
    private let disclosure = NSButton()
    private let copyDetails = ActionButton(L10n.text(.about,"updates.copyDetails")) {}
    private var detailsExpanded = false
    private var displayedFailure:String?
    private let retry = ActionButton(L10n.text(.about,"updates.retry")) {UpdateChecker.shared.check()}
    private let download = ActionButton(L10n.text(.about,"updates.download")) {}
    private let close = ActionButton(L10n.text(.about,"updates.close")) {}
    private let disableAutomatic = ActionButton(L10n.text(.about,"updates.disableAutomatic")) {}
    private let buttons = NSStackView()
    private let spacer = NSView()
    private var automaticPresentation = false

    static func show(check:Bool = true,activate:Bool = true,automaticallyPresented:Bool = false) {
        if current == nil {current = UpdateWindow()}
        guard let current else {return}
        current.automaticPresentation = automaticallyPresented
        if check {UpdateChecker.shared.check()}
        current.refresh()
        if !current.window.isVisible && !current.window.isMiniaturized {current.window.center()}
        if activate {
            InterfaceWindows.shared.focus(current.window)
        } else {
            InterfaceWindows.shared.opened(current.window)
            if !current.window.isVisible && !current.window.isMiniaturized {current.window.orderFront(nil)}
        }
    }
    override private init() {
        super.init()
        window.title = L10n.text(.about,"updates.title"); window.isReleasedWhenClosed = false; window.delegate = self
        window.collectionBehavior = [.fullScreenNone]
        let root = NSView(); window.contentView = root
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16; stack.distribution = .fill; stack.detachesHiddenViews = true
        status.font = .systemFont(ofSize:17,weight:.semibold)
        explanation.font = .systemFont(ofSize:13); explanation.textColor = .secondaryLabelColor
        versions.font = .systemFont(ofSize:12); timestamp.font = .systemFont(ofSize:11); timestamp.textColor = .secondaryLabelColor
        for field in [status,explanation,versions,timestamp] {field.isSelectable = true}
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        spinner.widthAnchor.constraint(equalToConstant:16).isActive = true
        spinner.heightAnchor.constraint(equalToConstant:16).isActive = true
        spinner.setAccessibilityLabel(L10n.text(.about,"updates.text"))
        heading.alignment = .centerY; heading.spacing = 8; heading.distribution = .fill; heading.detachesHiddenViews = true
        heading.addArrangedSubview(spinner); heading.addArrangedSubview(status)
        let metadata = NSStackView(views:[versions,timestamp])
        metadata.orientation = .vertical; metadata.distribution = .fill; metadata.alignment = .leading; metadata.spacing = 4
        for (scroll,text) in [(notesScroll,notes),(detailsScroll,details)] {
            scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
            text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
            text.minSize = .zero; text.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true; text.textContainer?.lineFragmentPadding = 0; text.textContainerInset = NSSize(width:0,height:4)
            scroll.documentView = text
        }
        MarkdownLayoutManager.install(in:notes)
        notesScroll.heightAnchor.constraint(equalToConstant:220).isActive = true
        detailsScroll.heightAnchor.constraint(equalToConstant:110).isActive = true
        details.font = .monospacedSystemFont(ofSize:11,weight:.regular)
        let notesTitle = NSTextField(labelWithString:L10n.text(.about,"updates.notesTitle")); notesTitle.font = .systemFont(ofSize:13,weight:.semibold)
        notesSection.orientation = .vertical; notesSection.distribution = .fill; notesSection.alignment = .leading; notesSection.spacing = 8
        notesSection.addArrangedSubview(notesTitle); notesSection.addArrangedSubview(notesScroll)
        notesScroll.widthAnchor.constraint(equalTo:notesSection.widthAnchor).isActive = true
        disclosure.setButtonType(.pushOnPushOff); disclosure.bezelStyle = .disclosure
        disclosure.title = ""; disclosure.target = self; disclosure.action = #selector(toggleDetails)
        disclosure.setAccessibilityLabel(L10n.text(.about,"updates.text.2"))
        let detailTitle = NSTextField(labelWithString:L10n.text(.about,"updates.detailTitle")); detailTitle.font = .systemFont(ofSize:12)
        let detailsRow = NSStackView(views:[disclosure,detailTitle,NSView(),copyDetails])
        detailsRow.alignment = .centerY; detailsRow.distribution = .fill; detailsRow.spacing = 6; detailsRow.detachesHiddenViews = true
        detailsSection.orientation = .vertical; detailsSection.distribution = .fill; detailsSection.alignment = .leading; detailsSection.spacing = 8; detailsSection.detachesHiddenViews = true
        detailsSection.addArrangedSubview(detailsRow); detailsSection.addArrangedSubview(detailsScroll)
        for view in [detailsRow,detailsScroll] {view.widthAnchor.constraint(equalTo:detailsSection.widthAnchor).isActive = true}
        CopyFeedback.attach(to:copyDetails) {UpdateChecker.shared.technicalDetails}
        close.callback = { [weak self] in self?.window.performClose(nil) }
        close.keyEquivalent = "\u{1b}"
        download.callback = {
            let url = UpdateChecker.shared.releaseURL ?? UpdateChecker.releases
            if !NSWorkspace.shared.open(url) {showError(L10n.text(.about,"updates.error"),PetFailure(message:url.absoluteString))}
        }
        disableAutomatic.callback = { [weak self] in
            PetPreferences.shared.set(false,for:"automaticallyCheckUpdates")
            self?.window.performClose(nil)
        }
        buttons.spacing = 8; buttons.distribution = .fill; buttons.alignment = .centerY; buttons.detachesHiddenViews = true
        spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        for view in [heading,explanation,metadata,notesSection,detailsSection,buttons] {stack.addArrangedSubview(view)}
        root.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:root.leadingAnchor,constant:24),
            stack.trailingAnchor.constraint(equalTo:root.trailingAnchor,constant:-24),
            stack.topAnchor.constraint(equalTo:root.topAnchor,constant:24)
        ])
        for view in [heading,explanation,metadata,notesSection,detailsSection,buttons] {view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true}
        NotificationCenter.default.addObserver(self,selector:#selector(refresh),name:UpdateChecker.didChange,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAutomaticOption),name:PetPreferences.didChange,object:nil)
    }
    @objc private func toggleDetails() {DisclosureMotion.update(in:window.contentView!) {detailsExpanded.toggle(); refresh()}}
    @objc private func refreshAutomaticOption() {disableAutomatic.isEnabled = PetPreferences.shared.bool("automaticallyCheckUpdates")}
    @objc private func refresh() {
        let checker = UpdateChecker.shared, failed = checker.failure != nil
        if displayedFailure != checker.failure?.detail {detailsExpanded = false; displayedFailure = checker.failure?.detail}
        status.stringValue = checker.headline
        spinner.isHidden = !checker.checking
        if checker.checking {spinner.startAnimation(nil)} else {spinner.stopAnimation(nil)}
        explanation.stringValue = checker.explanation; explanation.isHidden = checker.explanation.isEmpty
        let hasNotes = checker.release != nil && !failed
        notesSection.isHidden = !hasNotes; detailsSection.isHidden = !failed
        detailsScroll.isHidden = !detailsExpanded; copyDetails.isHidden = !detailsExpanded
        disclosure.state = detailsExpanded ? .on : .off
        disclosure.setAccessibilityLabel(detailsExpanded ? L10n.text(.about,"updates.refresh.text") : L10n.text(.about,"updates.text.2"))
        details.string = checker.technicalDetails
        versions.stringValue = L10n.format(.about,"updates.complete.error",String(describing:Paths.version)) + (hasNotes ? L10n.format(.about,"updates.refresh.text.2",String(describing:checker.release!.displayTag)) : "")
        timestamp.stringValue = L10n.text(.about,"updates.refresh.text.3")+checker.lastCheckText
        retry.keyEquivalent = failed ? "\r" : ""; download.keyEquivalent = !failed && !checker.checking ? "\r" : ""
        retry.title = failed ? L10n.text(.about,"updates.refresh.heading") : L10n.text(.about,"updates.retry"); retry.isEnabled = !checker.checking; retry.emphasize(failed)
        download.emphasize(!failed && !checker.checking)
        close.title = checker.checking ? L10n.text(.about,"updates.refresh.heading.2") : L10n.text(.about,"updates.close")
        disableAutomatic.isHidden = !automaticPresentation; refreshAutomaticOption()
        for view in buttons.arrangedSubviews {buttons.removeArrangedSubview(view); view.removeFromSuperview()}
        let actions = failed ? [disableAutomatic,spacer,download,close,retry] : [disableAutomatic,spacer,retry,close,download]
        for view in actions {buttons.addArrangedSubview(view)}
        let body = checker.release?.body?.trimmingCharacters(in:.whitespacesAndNewlines)
        notes.textStorage?.setAttributedString(MarkdownText.render(body?.isEmpty == false ? body! : L10n.text(.about,"updates.refresh.text.4"),font:.systemFont(ofSize:13)))
        let width = window.contentView!.bounds.width-48
        status.preferredMaxLayoutWidth = width-(checker.checking ? 24 : 0)
        explanation.preferredMaxLayoutWidth = width; versions.preferredMaxLayoutWidth = width
        window.contentView?.layoutSubtreeIfNeeded()
        let top = window.frame.maxY
        window.setContentSize(NSSize(width:600,height:ceil(stack.fittingSize.height)+44))
        window.setFrameOrigin(NSPoint(x:window.frame.minX,y:top-window.frame.height))
    }
    func windowWillClose(_ notification:Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.current = nil; UpdateChecker.shared.cancel()
    }
}
