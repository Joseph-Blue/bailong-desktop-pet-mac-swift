import AppKit
import AVFoundation

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
struct AnimationLoadTiming {
    let requestedAt: Double
    let firstFrameAt: Double
    let readyAt: Double
    var handedAt: Double?
    var displayedAt: Double?
}

// 帧数组构造后不再改变，CGImage 与 Data 均以只读方式跨队列使用。
final class Animation: NSObject, @unchecked Sendable {
    let frames: [Frame]
    let stream: StreamingAnimation?
    let fps: Double
    // 发布后仅在主线程记录交接和首次实际绘制，不保留历史帧或逐帧日志。
    var loadTiming: AnimationLoadTiming?
    init(_ frames: [Frame], stream: StreamingAnimation? = nil, fps: Double = 24, loadTiming: AnimationLoadTiming? = nil) {
        self.frames = frames; self.stream = stream; self.fps = fps; self.loadTiming = loadTiming
    }
    var frameCount: Int { stream?.frameCount ?? frames.count }
    var retainedFrames: [Frame] { stream?.retainedFrames(first:frames.first) ?? frames }
}

private final class WeakAnimation {
    weak var value: Animation?
    init(_ value: Animation) { self.value = value }
}

// 可变解码状态由 lock 保护；默认流式读取，CPU 工作区随当前动画复用，整段预加载按偏好启用。
final class Decoder: @unchecked Sendable {
    static let openingCacheLimit = 24 * 1024 * 1024
    private static let openingFrameLimit = 6
    private struct OpeningKey: Equatable {
        let file: String
        let resolution: Int
        let fpsLimit: Double?
        let cappedPlaybackRate: Double?
    }
    private struct Opening {
        let key: OpeningKey
        let entries: [StreamingAnimation.Entry]
        let bytes: Int
    }
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var worker: Task<Void, Never>?
    private var stream: StreamingAnimation?
    private var generation = 0
    private var bufferCapacity = 12
    private var preloadWhole = false
    private var openingCacheEnabled = false
    private var openingCacheRevision = 0
    private var openings = [Opening]() // 从最近最少使用到最近使用。
    private var openingBytes = 0, openingHits = 0
    private var preloadProgress: (id: String, frames: Int, total: Int)?
    func preloadingStatistics() -> (id: String, frames: Int, total: Int)? { lock.withLock { preloadProgress } }
    private var resident = [String: WeakAnimation]()
    func residentFrameStatistics() -> (clips: Int, frames: Int, bytes: Int, openingClips: Int, openingBytes: Int, hits: Int) {
        lock.withLock {
            let live = resident.values.compactMap { $0.value }
            var unique = [ObjectIdentifier:Int]()
            for animation in live { for frame in animation.retainedFrames { unique[ObjectIdentifier(frame.image)] = frame.cost } }
            for opening in openings { for entry in opening.entries { unique[ObjectIdentifier(entry.frame.image)] = entry.frame.cost } }
            return (live.count,unique.count,unique.values.reduce(0,+),openings.count,openingBytes,openingHits)
        }
    }
    func setOpeningCacheEnabled(_ enabled: Bool) {
        lock.withLock {
            guard openingCacheEnabled != enabled else { return }
            openingCacheEnabled = enabled; clearOpenings()
        }
    }
    func discardOpeningCache() { lock.withLock { clearOpenings() } }
    private func clearOpenings() {
        openingCacheRevision += 1; openings.removeAll(); openingBytes = 0
    }
    private func rememberOpening(key: OpeningKey, entries: [StreamingAnimation.Entry]) {
        let bytes = entries.reduce(0) { $0 + $1.frame.cost }
        guard !entries.isEmpty, bytes <= Self.openingCacheLimit else { return }
        if let index = openings.firstIndex(where:{$0.key == key}) { openingBytes -= openings.remove(at:index).bytes }
        while openingBytes + bytes > Self.openingCacheLimit { openingBytes -= openings.removeFirst().bytes }
        openings.append(Opening(key:key,entries:entries,bytes:bytes)); openingBytes += bytes
    }
    func configure(bufferCapacity: Int, preloadWhole: Bool) {
        cancel()
        lock.withLock {
            self.bufferCapacity = bufferCapacity; self.preloadWhole = preloadWhole
            resident.removeAll(); clearOpenings()
        }
    }
    func cancel() {
        cancelLoad(keepingStream: false)
    }
    private func cancelLoad(keepingStream: Bool) {
        let (pending, streaming) = lock.withLock { () -> (Task<Void, Never>?, StreamingAnimation?) in
            generation += 1; preloadProgress = nil
            let oldStream = keepingStream ? nil : stream
            if !keepingStream { stream = nil }
            let pending = worker; worker = nil
            return (pending, oldStream)
        }
        streaming?.stop(); pending?.cancel()
    }
    func close() {
        let activeStream = lock.withLock { stream }
        cancel(); activeStream?.waitUntilStopped(); group.wait()
        lock.withLock { resident.removeAll(); clearOpenings() }
    }
    private func current(_ token: Int) -> Bool { lock.withLock { generation == token } }
    func load(_ clip: Clip, resolution: Int, fpsLimit: Double?, playbackRate: Double, cacheOpening: Bool,
              framesReady: @escaping () -> Void, first: @escaping (Frame) -> Void, completion: @escaping (Result<Animation, Error>) -> Void) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        // 新片段准备期间继续供应当前片段的帧；只取消上一份尚未完成的加载。
        cancelLoad(keepingStream: true)
        let (token, capacity, preload, cacheRevision) = lock.withLock { (generation, bufferCapacity, preloadWhole, openingCacheRevision) }
        let file = clip.playbackFile ?? clip.file
        let key = OpeningKey(file:file,resolution:resolution,fpsLimit:fpsLimit,cappedPlaybackRate:fpsLimit == nil ? nil : playbackRate)
        group.enter()
        lock.withLock { worker = Task.detached(priority: .userInitiated) { [self] in
            defer { group.leave() }
            do {
                let asset = AVURLAsset(url: Paths.assets.appendingPathComponent(file))
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw PetFailure(message: "「\(clip.title)」没有视频轨道。")
                }
                guard current(token) else { return }
                let rate = try await track.load(.nominalFrameRate)
                guard rate.isFinite && rate > 0 else {throw PetFailure(message:"「\(clip.title)」缺少有效的素材帧率。")}
                let range = try await track.load(.timeRange)
                guard current(token) else { return }
                let streaming = StreamingAnimation(asset: asset, track: track, capacity: capacity, resolution: resolution,
                    frameCount: max(1, Int((range.duration.seconds * Double(rate)).rounded())),
                    startTime: range.start.seconds, sourceFPS: Double(rate), fpsLimit: fpsLimit, playbackRate: playbackRate,
                    onFramesReady: { [weak self] source in
                        guard let self, self.lock.withLock({ self.stream === source }) else { return }
                        framesReady()
                    },
                    onFailure: { [weak self] error in
                        if self?.current(token) == true { completion(.failure(error)) }
                    })
                if preload {
                    lock.withLock { if generation == token { preloadProgress = (clip.id, 0, streaming.frameCount) } }
                    defer { lock.withLock { if generation == token { preloadProgress = nil } } }
                    guard let frames = try streaming.preload(isCurrent: { self.current(token) }, progress: { count in
                        self.lock.withLock { if self.generation == token { self.preloadProgress = (clip.id, count, streaming.frameCount) } }
                    }), current(token) else { return }
                    guard !frames.isEmpty else { throw PetFailure(message: "「\(clip.title)」没有可播放的帧。") }
                    let readyAt = ProcessInfo.processInfo.systemUptime
                    let timing = AnimationLoadTiming(requestedAt:requestedAt,firstFrameAt:streaming.firstFramePreparedAt!,readyAt:readyAt)
                    let animation = Animation(frames,fps:Double(rate),loadTiming:timing)
                    publish(animation, clip: clip, token: token, first: first, completion: completion)
                    return
                }
                let (canCache, opening) = lock.withLock { () -> (Bool,[StreamingAnimation.Entry]) in
                    guard cacheOpening, openingCacheEnabled, cacheRevision == openingCacheRevision, generation == token else { return (false,[]) }
                    guard let index = openings.firstIndex(where:{$0.key == key}) else { return (true,[]) }
                    let hit = openings.remove(at:index); openings.append(hit)
                    return (true,hit.entries)
                }
                guard let firstFrame = try streaming.prepareForPlayback(playbackRate:playbackRate,opening:opening,isCurrent: { self.current(token) }) else { return }
                let timing = AnimationLoadTiming(requestedAt:requestedAt,firstFrameAt:streaming.firstFramePreparedAt!,readyAt:ProcessInfo.processInfo.systemUptime)
                let animation = Animation([firstFrame], stream: streaming,fps:Double(rate),loadTiming:timing)
                let entries = canCache ? streaming.openingFrames(limit:Self.openingFrameLimit) : []
                publish(animation,clip:clip,token:token,cache:(key,entries,cacheRevision,!opening.isEmpty),first:first,completion:completion)
            } catch {
                DispatchQueue.main.async { if self.current(token) { completion(.failure(error)) } }
            }
        } }
    }
    private func publish(_ animation: Animation, clip: Clip, token: Int,
                         cache: (key: OpeningKey, entries: [StreamingAnimation.Entry], revision: Int, hit: Bool)? = nil,
                         first: @escaping (Frame) -> Void, completion: @escaping (Result<Animation, Error>) -> Void) {
        DispatchQueue.main.async {
            guard self.current(token) else { animation.stream?.stop(); return }
            animation.loadTiming?.handedAt = ProcessInfo.processInfo.systemUptime
            let previous = self.lock.withLock { () -> StreamingAnimation? in
                let previous = self.stream
                self.stream = animation.stream
                self.resident[clip.id] = WeakAnimation(animation)
                if let cache, self.openingCacheEnabled, cache.revision == self.openingCacheRevision {
                    self.rememberOpening(key:cache.key,entries:cache.entries)
                    if cache.hit { self.openingHits += 1 }
                }
                return previous
            }
            first(animation.frames[0])
            // 首次显示的回调能触发新动作；已被替换时不再发布旧加载结果。
            guard self.current(token) else { previous?.stop(); return }
            completion(.success(animation))
            previous?.stop()
            animation.stream?.request(0)
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
