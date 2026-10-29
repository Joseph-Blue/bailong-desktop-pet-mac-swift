import AppKit

struct PetFailure: LocalizedError { let message: String; var errorDescription: String? { message } }

enum Paths {
    static let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let resources: URL = {
        if Bundle.main.bundleURL.pathExtension == "app" { return Bundle.main.resourceURL! }
        return project.appendingPathComponent("local-assets")
    }()
    static let assets = resources.appendingPathComponent("outputs/白龙桌宠素材")
    static let ffmpeg = resources.appendingPathComponent("tools/ffmpeg")
    static let data = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BAILONG_DATA_DIR"] ??
        NSHomeDirectory() + "/Library/Application Support/BailongPetAppKit")
    static var version: String {
        let url = Bundle.main.bundleURL.pathExtension == "app" ? resources.appendingPathComponent("VERSION") : project.appendingPathComponent("VERSION")
        return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.2.1"
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
        return pixels[(y * 512 + x) * 4 + 3]
    }
}
final class Animation: NSObject {
    let frames: [Frame]
    init(_ frames: [Frame]) { self.frames = frames }
    var cost: Int { frames.count * 512 * 512 * 4 }
}

final class Decoder {
    private let queue = DispatchQueue(label: "白龙娘透明动画解码", qos: .userInitiated)
    private let lock = NSLock()
    private var process: Process?
    private var generation = 0
    private let cache = NSCache<NSString, Animation>()
    private var pinned = [String:Animation]()
    private let pinnedIDs: Set<String> = ["idle", "idle2", "drag", "landing"]
    init() { cache.totalCostLimit = 192 * 1024 * 1024 }
    private func cached(_ id: String) -> Animation? {
        lock.lock(); let value = pinned[id]; lock.unlock()
        return value ?? cache.object(forKey:id as NSString)
    }
    func thumbnail(_ clip: Clip) -> NSImage? {
        cached(clip.id)?.frames.first.map {NSImage(cgImage:$0.image,size:NSSize(width:36,height:36))}
    }
    // 只预热基础待机、拖拽和落地。用户发起新动作时可立即中断预热。
    func warm(_ clips: [Clip]) {
        lock.lock(); let token = generation; lock.unlock()
        queue.async { [self] in
            for clip in clips where cached(clip.id) == nil {
                guard current(token) else { return }
                decode(clip, token:token, first:{ _ in }, completion:{ _ in })
            }
        }
    }
    func cancel() {
        lock.lock(); generation += 1
        let task = process
        lock.unlock()
        if let task, task.isRunning {
            task.terminate()
            DispatchQueue.global().asyncAfter(deadline:.now()+1) {
                if task.isRunning { kill(task.processIdentifier,SIGKILL) }
            }
        }
    }
    func close() {
        cancel()
        // 退出前等待自有解码任务排空管道；取消超时的 FFmpeg 会被现有定时器回收。
        queue.sync {}
    }
    private func current(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == token }
    func load(_ clip: Clip, first: @escaping (Frame) -> Void, completion: @escaping (Result<Animation, Error>) -> Void) {
        cancel()
        lock.lock(); let token = generation; lock.unlock()
        if let value = cached(clip.id) { completion(.success(value)); return }
        queue.async { [self] in decode(clip,token:token,first:first,completion:completion) }
    }
    private func decode(_ clip: Clip, token: Int, first: @escaping (Frame) -> Void, completion: @escaping (Result<Animation, Error>) -> Void) {
            guard current(token) else { return }
            if let value = cached(clip.id) {
                DispatchQueue.main.async { if self.current(token) { completion(.success(value)) } }; return
            }
            let task = Process(), output = Pipe()
            let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                FileManager.default.createFile(atPath: errorURL.path, contents: nil)
                let errors = try FileHandle(forWritingTo: errorURL)
                defer { try? errors.close(); try? FileManager.default.removeItem(at: errorURL) }
                task.executableURL = Paths.ffmpeg
                // 输入前指定 libvpx-vp9；通用 VP9 解码器可能丢弃 WebM alpha。
                task.arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-c:v", "libvpx-vp9", "-threads", "2", "-i", Paths.assets.appendingPathComponent(clip.playbackFile ?? clip.file).path,
                    "-an", "-vf", "scale=512:512:flags=lanczos", "-pix_fmt", "rgba", "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"]
                task.standardOutput = output; task.standardError = errors
                lock.lock()
                guard generation == token else { lock.unlock(); return }
                process = task
                do { try task.run() } catch { lock.unlock(); throw error }
                lock.unlock()
                defer { if task.isRunning { task.terminate() }; try? output.fileHandleForReading.close() }
                var frames = [Frame](), pending = Data()
                var referenceBounds = CGRect.zero
                let stride = 512 * 512 * 4
                while true {
                    let part = output.fileHandleForReading.readData(ofLength: stride - pending.count)
                    if part.isEmpty { break }
                    // 取消后仍排空管道，避免 FFmpeg 卡在写入、waitUntilExit 永不返回。
                    if !current(token) { pending.removeAll(); continue }
                    pending.append(part)
                    if pending.count == stride {
                        let pixels = pending; pending = Data()
                        let provider = CGDataProvider(data: pixels as CFData)!
                        let image = CGImage(width: 512, height: 512, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 2048, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                            decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
                        // 仅首帧求稳定边界；透明命中直接读取当前帧的 alpha。
                        if frames.isEmpty {
                            var x0 = 512, y0 = 512, x1 = -1, y1 = -1
                            pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                                for y in 0..<512 { for x in 0..<512 where bytes[(y * 512 + x) * 4 + 3] > 0 {
                                    x0 = min(x0,x); y0 = min(y0,y); x1 = max(x1,x); y1 = max(y1,y)
                                }}
                            }
                            referenceBounds = x1 < 0 ? .zero : CGRect(x:x0,y:y0,width:x1-x0+1,height:y1-y0+1)
                        }
                        let frame = Frame(image:image,pixels:pixels,bounds:referenceBounds)
                        frames.append(frame)
                        if frames.count == 1 { DispatchQueue.main.async { if self.current(token) { first(frame) } } }
                    }
                }
                task.waitUntilExit()
                guard current(token) else { return }
                if task.terminationStatus != 0 || frames.isEmpty || !pending.isEmpty {
                    let detail = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
                    throw PetFailure(message: "无法解码「\(clip.title)」\n\(detail)")
                }
                let animation = Animation(frames)
                if pinnedIDs.contains(clip.id) { lock.lock(); pinned[clip.id] = animation; lock.unlock() }
                else { cache.setObject(animation, forKey:clip.id as NSString,cost:animation.cost) }
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
