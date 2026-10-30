import AppKit
import AVFoundation

// 独立预览程序仅加载包内 HEVC，不读取桌宠设置、历史或 Codex 数据。
private struct PreviewCatalog: Decodable {
    struct Sample: Decodable { let name: String; let file: String }
    let version: String
    let samples: [Sample]
}

private final class VideoView: NSView {
    let video = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        video.videoGravity = .resizeAspect
        layer?.addSublayer(video)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); video.frame = bounds }
}

private final class PreviewApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let video = VideoView(frame: .zero)
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var observation: NSKeyValueObservation?
    private let clips = NSPopUpButton()
    private let backgrounds = NSPopUpButton()
    private let speeds = NSPopUpButton()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private var catalog: PreviewCatalog!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            catalog = try JSONDecoder().decode(PreviewCatalog.self,
                from: Data(contentsOf: resources.appendingPathComponent("samples/samples.json")))
            guard !catalog.samples.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        } catch {
            let alert = NSAlert(error: error); alert.runModal(); NSApp.terminate(nil); return
        }
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "退出原生动画预览", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        #if arch(arm64)
        let architecture = "Apple Silicon"
        #else
        let architecture = "Intel"
        #endif
        window.title = "白龙娘原生动画预览 · \(catalog.version) · \(architecture)"
        window.minSize = NSSize(width: 460, height: 540)
        let content = window.contentView!
        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 12
        clips.addItems(withTitles: catalog.samples.map(\.name))
        clips.target = self; clips.action = #selector(selectClip)
        backgrounds.addItems(withTitles: ["浅色背景", "深色背景", "桌面透明背景"])
        backgrounds.target = self; backgrounds.action = #selector(selectBackground)
        speeds.addItems(withTitles: ["0.5×", "1×", "2×"])
        speeds.selectItem(at: 1)
        speeds.target = self; speeds.action = #selector(selectSpeed)
        for control in [clips, backgrounds, speeds] { controls.addArrangedSubview(control) }
        notice.font = .systemFont(ofSize: 12)
        notice.textColor = .secondaryLabelColor
        notice.isSelectable = true
        for view in [controls, video, notice] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            controls.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            video.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 16),
            video.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            video.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            video.bottomAnchor.constraint(equalTo: notice.topAnchor, constant: -12),
            notice.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            notice.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            notice.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        video.video.player = player
        selectBackground()
        selectClip()
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func selectClip() {
        observation = nil
        player.pause()
        looper?.disableLooping(); looper = nil
        player.removeAllItems()
        let sample = catalog.samples[clips.indexOfSelectedItem]
        let url = Bundle.main.resourceURL!.appendingPathComponent("samples/\(sample.file)")
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        observation = looper?.observe(\.status, options: [.initial, .new]) { [weak self] loop, _ in
            if loop.status == .failed {
                let message: String
                if let error = loop.error as NSError? {
                    let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
                    message = "\(error.localizedDescription)（\(error.domain) \(error.code)）"
                        + (underlying.map { "\n底层错误：\($0.domain) \($0.code)" } ?? "")
                } else {
                    message = "播放器未提供具体错误"
                }
                DispatchQueue.main.async { self?.notice.stringValue = "播放失败：\(message)" }
            }
        }
        notice.stringValue = "自动循环播放；可切换动作、背景和速度。此预览用于查看画面，不包含桌宠交互。"
        selectSpeed()
    }

    @objc private func selectSpeed() {
        player.playImmediately(atRate: [Float(0.5), 1, 2][speeds.indexOfSelectedItem])
    }

    @objc private func selectBackground() {
        let index = backgrounds.indexOfSelectedItem
        window.isOpaque = index != 2
        window.backgroundColor = index == 0 ? .white : index == 1 ? .black : .clear
        window.hasShadow = index != 2
        notice.textColor = index == 0 ? .darkGray : index == 1 ? .lightGray : .labelColor
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        observation = nil; player.pause(); looper?.disableLooping(); player.removeAllItems()
    }
}

@main
struct NativePreviewMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewApp()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
