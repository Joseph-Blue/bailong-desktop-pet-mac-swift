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
    static func readVersion() throws -> String {
        let url = Bundle.main.bundleURL.pathExtension == "app" ? resources.appendingPathComponent("VERSION") : project.appendingPathComponent("VERSION")
        let version = try String(contentsOf:url,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
        guard SemanticVersion(version) != nil else {throw PetFailure(message:"VERSION 中的版本号无法识别。")}
        return version
    }
    static var version:String {
        switch Result(catching:readVersion) {
        case .success(let value): return value
        case .failure: return "版本不可读"
        }
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
    var alphaOnly = false
    var cost: Int { image.bytesPerRow * image.height + (alphaOnly ? pixels.count : 0) }
    func alpha(x: Int, y: Int) -> UInt8 {
        guard (0..<512).contains(x), (0..<512).contains(y) else { return 0 }
        let px = min(image.width - 1, x * image.width / 512)
        let py = min(image.height - 1, y * image.height / 512)
        return pixels[alphaOnly ? py * image.width + px : py * image.bytesPerRow + px * 4 + 3]
    }
}
// 帧数组构造后不再改变，CGImage 与 Data 均以只读方式跨队列使用。
final class Animation: NSObject, @unchecked Sendable {
    let frames: [Frame]
    let stream: StreamingAnimation?
    let fps: Double
    init(_ frames: [Frame], stream: StreamingAnimation? = nil, fps: Double = 24) { self.frames = frames; self.stream = stream; self.fps = fps }
    var frameCount: Int { stream?.frameCount ?? frames.count }
    var residentCount: Int { stream.map { $0.statistics(retaining: frames.first).frames } ?? frames.count }
    var cost: Int { stream?.statistics(retaining: frames.first).bytes ?? frames.reduce(0) { $0 + $1.cost } }
}

private final class WeakAnimation {
    weak var value: Animation?
    init(_ value: Animation) { self.value = value }
}

// 可变解码状态由 lock 保护；Core Image 上下文复用，默认流式读取，整段预加载按偏好启用。
final class Decoder: @unchecked Sendable {
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var worker: Task<Void, Never>?
    private var stream: StreamingAnimation?
    private var generation = 0
    private var bufferCapacity = 24
    private var resolution = 512
    private var preloadWhole = false
    private var preloadProgress: (id: String, frames: Int, total: Int)?
    func preloadingStatistics() -> (id: String, frames: Int, total: Int)? { lock.withLock { preloadProgress } }
    private var resident = [String: WeakAnimation]()
    private let context = CIContext(options: [.cacheIntermediates: false, .outputPremultiplied: true])
    func residentFrameStatistics() -> (clips: Int, frames: Int, bytes: Int) {
        lock.withLock {
            let live = resident.values.compactMap { $0.value }
            return (live.count, live.reduce(0) { $0 + $1.residentCount }, live.reduce(0) { $0 + $1.cost })
        }
    }
    func configure(bufferCapacity: Int, resolution: Int, preloadWhole: Bool) {
        cancel()
        lock.withLock {
            self.bufferCapacity = bufferCapacity; self.resolution = resolution; self.preloadWhole = preloadWhole
            resident.removeAll()
        }
        context.clearCaches()
    }
    func cancel() {
        let (pending, streaming) = lock.withLock { () -> (Task<Void, Never>?, StreamingAnimation?) in
            generation += 1; preloadProgress = nil
            let oldStream = stream; stream = nil
            return (worker, oldStream)
        }
        streaming?.stop(); pending?.cancel()
    }
    func close() {
        let activeStream = lock.withLock { stream }
        cancel(); activeStream?.waitUntilStopped(); group.wait()
        context.clearCaches()
        lock.withLock { resident.removeAll() }
    }
    private func current(_ token: Int) -> Bool { lock.withLock { generation == token } }
    func load(_ clip: Clip, first: @escaping (Frame) -> Void, completion: @escaping (Result<Animation, Error>) -> Void) {
        cancel()
        let (token, capacity, side, preload) = lock.withLock { (generation, bufferCapacity, resolution, preloadWhole) }
        group.enter()
        lock.withLock { worker = Task.detached(priority: .userInitiated) { [self] in
            defer { group.leave() }
            do {
                let asset = AVURLAsset(url: Paths.assets.appendingPathComponent(clip.playbackFile ?? clip.file))
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw PetFailure(message: "「\(clip.title)」没有视频轨道。")
                }
                guard current(token) else { return }
                let rate = try await track.load(.nominalFrameRate)
                guard rate.isFinite && rate > 0 else {throw PetFailure(message:"「\(clip.title)」缺少有效的素材帧率。")}
                let range = try await track.load(.timeRange)
                guard current(token) else { return }
                let streaming = StreamingAnimation(asset: asset, track: track, context: context, capacity: capacity, resolution: side,
                    frameCount: max(1, Int((range.duration.seconds * Double(rate)).rounded())),
                    startTime: range.start.seconds, onFailure: { [weak self] error in
                        if self?.current(token) == true { completion(.failure(error)) }
                    })
                if preload {
                    lock.withLock { if generation == token { preloadProgress = (clip.id, 0, streaming.frameCount) } }
                    defer { lock.withLock { if generation == token { preloadProgress = nil } } }
                    guard let frames = try streaming.preload(isCurrent: { self.current(token) }, progress: { count in
                        self.lock.withLock { if self.generation == token { self.preloadProgress = (clip.id, count, streaming.frameCount) } }
                    }), current(token) else { return }
                    guard let firstFrame = frames.first else { throw PetFailure(message: "「\(clip.title)」没有可播放的帧。") }
                    let animation = Animation(frames,fps:Double(rate))
                    lock.withLock { if generation == token { resident[clip.id] = WeakAnimation(animation) } }
                    DispatchQueue.main.async {
                        if self.current(token) { first(firstFrame); completion(.success(animation)) }
                    }
                    return
                }
                let firstFrame = try streaming.prime()
                let animation = Animation([firstFrame], stream: streaming,fps:Double(rate))
                let accepted = lock.withLock { () -> Bool in
                    guard generation == token else { return false }
                    stream = streaming; resident[clip.id] = WeakAnimation(animation); return true
                }
                guard accepted else { streaming.stop(); return }
                DispatchQueue.main.async {
                    if self.current(token) {
                        first(firstFrame); completion(.success(animation)); streaming.request(0)
                    }
                }
            } catch {
                DispatchQueue.main.async { if self.current(token) { completion(.failure(error)) } }
            }
        } }
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
