import AppKit
import AVFoundation
import CoreImage

struct PetFailure: LocalizedError { let message: String; var errorDescription: String? { message } }

enum Paths {
    static let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let resources: URL = {
        if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main.resourceURL! }
        return project.appendingPathComponent("local-assets")
    }()
    static let assets = resources.appendingPathComponent(Bundle.main.bundleURL.pathExtension == "app" ? "outputs/白龙桌宠素材" : "native-hevc/catalog")
    static let data = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BAILONG_DATA_DIR"] ??
        NSHomeDirectory() + "/Library/Application Support/BailongPetAppKit")
    static var version: String {
        let url = Bundle.main.bundleURL.pathExtension == "app" ? resources.appendingPathComponent("VERSION") : project.appendingPathComponent("VERSION")
        return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.3.0-dev.3"
    }
}

struct Clip: Decodable {
    let id: String
    let name: String?
    let file: String
    let playbackFile: String?
    let durationMs: Double
    let renderScale: Double?
    let renderOffset: [Double]?
    let line: String?
    let number: String?
    let sourceFacing: String?
    let movementSpeed: Double?
    let movementAngleRange: [Double]?
    let moveStartMs: Double?
    let moveStopMs: Double?
    var title: String { name ?? ["idle": "默认待机", "idle2": "待机动作02", "drag": "拖拽", "landing": "落地", "quota": "查询额度"][id] ?? id }
}
struct Catalog: Decodable {
    let idle: Clip
    let additionalIdleAnimations: [Clip]
    let variants: [Clip]
    let workAnimations: [Clip?]
    let movementAnimations: [Clip]
    let dragAnimation: Clip
    let landingAnimation: Clip
    let quotaAnimation: Clip
    var idles: [Clip] { [idle] + additionalIdleAnimations.prefix(1) }
    var extras: [Clip] { Array(additionalIdleAnimations.dropFirst()) }
    var work: [Clip] { workAnimations.compactMap { $0 } }
    var all: [Clip] { idles + extras + variants + work + movementAnimations + [dragAnimation, landingAnimation, quotaAnimation] }
    static func load() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: Paths.assets.appendingPathComponent("素材清单.json")))
    }
}

struct Frame {
    let image: CGImage
    let pixels: Data
    let bounds: CGRect
    func alpha(x: Int, y: Int) -> UInt8 {
        guard (0..<512).contains(x), (0..<512).contains(y) else { return 0 }
        return pixels[y * image.bytesPerRow + x * 4 + 3]
    }
}
// 帧数组构造后不再改变，CGImage 与 Data 均以只读方式跨队列使用。
final class Animation: NSObject, @unchecked Sendable {
    let frames: [Frame]
    init(_ frames: [Frame]) { self.frames = frames }
    var cost: Int { frames.count * 512 * 512 * 4 }
}

// 可变解码状态由 lock 保护；NSCache / CIContext 自身支持并发访问。
final class Decoder: @unchecked Sendable {
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var worker: Task<Void, Never>?
    private var reader: AVAssetReader?
    private var generation = 0
    private let cache = NSCache<NSString, Animation>()
    private var pinned = [String: Animation]()
    private let pinnedIDs: Set<String> = ["idle", "idle2", "drag", "landing"]
    private let context = CIContext(options: [.cacheIntermediates: false, .outputPremultiplied: true])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    init() { cache.totalCostLimit = 192 * 1024 * 1024 }
    private func cached(_ id: String) -> Animation? {
        lock.withLock { pinned[id] } ?? cache.object(forKey: id as NSString)
    }
    func thumbnail(_ clip: Clip) -> NSImage? {
        cached(clip.id)?.frames.first.map { NSImage(cgImage: $0.image, size: NSSize(width: 36, height: 36)) }
    }
    // 保留原有首帧、基础动作预热和缓存接口，动画调度与透明命中继续使用同一帧。
    func warm(_ clips: [Clip]) {
        let token = lock.withLock { generation }
        group.enter()
        lock.withLock { worker = Task.detached(priority: .userInitiated) { [self] in
            defer { group.leave() }
            for clip in clips where cached(clip.id) == nil {
                guard current(token) else { return }
                await decode(clip, token: token, first: { _ in }, completion: { result in
                    if case .failure(let error) = result { NSLog("动画预热失败：%@", error.localizedDescription) }
                })
            }
        } }
    }
    func cancel() {
        let (active, pending) = lock.withLock { () -> (AVAssetReader?, Task<Void, Never>?) in
            generation += 1
            return (reader, worker)
        }
        pending?.cancel()
        active?.cancelReading()
    }
    func close() {
        cancel()
        // 只有本进程内的原生 reader；等待取消完成，不启动或遗留解码子进程。
        group.wait()
        cache.removeAllObjects()
        lock.withLock { pinned.removeAll() }
    }
    private func current(_ token: Int) -> Bool { lock.withLock { generation == token } }
    func load(_ clip: Clip, first: @escaping (Frame) -> Void, completion: @escaping (Result<Animation, Error>) -> Void) {
        cancel()
        let token = lock.withLock { generation }
        if let value = cached(clip.id) { completion(.success(value)); return }
        group.enter()
        lock.withLock { worker = Task.detached(priority: .userInitiated) { [self] in
            defer { group.leave() }
            await decode(clip, token: token, first: first, completion: completion)
        } }
    }
    private func decode(_ clip: Clip, token: Int, first: @escaping (Frame) -> Void,
                        completion: @escaping (Result<Animation, Error>) -> Void) async {
        guard current(token) else { return }
        if let value = cached(clip.id) {
            DispatchQueue.main.async { if self.current(token) { completion(.success(value)) } }; return
        }
        do {
            let asset = AVURLAsset(url: Paths.assets.appendingPathComponent(clip.playbackFile ?? clip.file))
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw PetFailure(message: "「\(clip.title)」没有视频轨道。")
            }
            guard current(token) else { return }
            let decoding = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            output.alwaysCopiesSampleData = false
            decoding.add(output)
            let started = lock.withLock { () -> Bool in
                guard generation == token else { return false }
                reader = decoding
                return decoding.startReading()
            }
            defer {
                decoding.cancelReading()
                lock.withLock { if reader === decoding { reader = nil } }
            }
            guard current(token) else { return }
            guard started else { throw decoding.error ?? PetFailure(message: "无法开始解码「\(clip.title)」。") }
            var frames = [Frame]()
            var referenceBounds = CGRect.zero
            while current(token) {
                let frame: Frame? = try autoreleasepool {
                    guard let sample = output.copyNextSampleBuffer() else { return nil }
                    guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
                        throw PetFailure(message: "「\(clip.title)」包含无像素数据的视频帧。")
                    }
                    let source = CIImage(cvPixelBuffer: buffer)
                    let scaled = source.applyingFilter("CILanczosScaleTransform", parameters: [
                        kCIInputScaleKey: 512 / source.extent.height,
                        kCIInputAspectRatioKey: source.extent.height / source.extent.width
                    ])
                    // 由 Core Image 创建标准 CGImage，显示和命中读取同一张图的 RGBA 数据。
                    // 不手工重排视频缓冲区的行方向，也不把 BGRA 当成 RGBA。
                    guard let image = context.createCGImage(scaled,
                        from: CGRect(x: 0, y: 0, width: 512, height: 512), format: .RGBA8, colorSpace: colorSpace),
                        let data = image.dataProvider?.data else {
                        throw PetFailure(message: "无法创建「\(clip.title)」的透明画面。")
                    }
                    let pixels = data as Data
                    if frames.isEmpty {
                        var x0 = 512, y0 = 512, x1 = -1, y1 = -1
                        pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                            for y in 0..<512 { for x in 0..<512 where bytes[y * image.bytesPerRow + x * 4 + 3] > 0 {
                                x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
                            } }
                        }
                        referenceBounds = x1 < 0 ? .zero : CGRect(x: x0, y: y0, width: x1-x0+1, height: y1-y0+1)
                    }
                    return Frame(image: image, pixels: pixels, bounds: referenceBounds)
                }
                guard let frame else { break }
                frames.append(frame)
                if frames.count == 1 { DispatchQueue.main.async { if self.current(token) { first(frame) } } }
            }
            guard current(token) else { return }
            guard decoding.status == .completed, !frames.isEmpty else {
                throw decoding.error ?? PetFailure(message: "「\(clip.title)」的视频解码没有完整结束。")
            }
            let animation = Animation(frames)
            lock.withLock {
                guard generation == token else { return }
                if pinnedIDs.contains(clip.id) { pinned[clip.id] = animation }
                else { cache.setObject(animation, forKey: clip.id as NSString, cost: animation.cost) }
            }
            DispatchQueue.main.async { if self.current(token) { completion(.success(animation)) } }
        } catch {
            DispatchQueue.main.async { if self.current(token) { completion(.failure(error)) } }
        }
    }
}

// 依据作者 app/movement.py，使用整条射线裁短距离，不分别裁剪横纵轴。
func movementTarget(origin: CGPoint, bounds: CGRect, size: Double, clip: Clip) -> CGPoint? {
    let left = bounds.minX, right = bounds.maxX, top = bounds.minY, bottom = bounds.maxY
    let run = (clip.moveStopMs ?? clip.durationMs) - (clip.moveStartMs ?? 0)
    let speed = clip.movementSpeed ?? (clip.number == "01" ? 0.5 : 1)
    let desired = Double.random(in: size * 0.65...size * 1.25) * max(0.25, run / 2583) * speed
    var directions = [-1.0, 1.0]
    let margin = size * 0.65
    if origin.x - left < margin && right - origin.x > origin.x - left { directions = [1] }
    else if right - origin.x < margin && origin.x - left > right - origin.x { directions = [-1] }
    let facing = clip.sourceFacing == "left" ? -1.0 : 1.0
    guard directions.contains(facing) else { return nil }
    var candidates = [CGPoint]()
    for _ in 0..<48 {
        var sign = Bool.random() ? 1.0 : -1.0
        if origin.y - top < margin && bottom - origin.y > origin.y - top { sign = 1 }
        else if bottom - origin.y < margin && origin.y - top > bottom - origin.y { sign = -1 }
        let angle: Double
        if let range = clip.movementAngleRange {
            let limits = sign > 0 ? [45.0, 65.0] : range
            angle = sign * Double.random(in: limits[0] + 1...limits[1] - 1) * .pi / 180
        } else {
            angle = sign * Double.random(in: 0...45) * .pi / 180
        }
        let dx = facing * cos(angle), dy = sin(angle)
        var length = desired
        length = min(length, dx > 0 ? (right - origin.x) / dx : (left - origin.x) / dx)
        if dy != 0 { length = min(length, dy > 0 ? (bottom - origin.y) / dy : (top - origin.y) / dy) }
        if length >= min(48, size * 0.2) { candidates.append(CGPoint(x: origin.x + dx * length, y: origin.y + dy * length)) }
    }
    return candidates.randomElement()
}
