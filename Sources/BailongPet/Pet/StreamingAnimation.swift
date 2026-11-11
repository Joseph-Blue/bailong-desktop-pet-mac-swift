import AVFoundation

// 在源时间轴上选取覆盖目标时刻的帧；跳过的样本仍由 HEVC 解码，但不做像素转换。
struct AnimationFrameSampler {
    private var previousLimit: Double?
    private var nextTime = 0.0
    mutating func presentationTime(sourceTime: Double, frameDuration: Double, limit: Double?) -> Double? {
        if limit != previousLimit { nextTime = sourceTime; previousLimit = limit }
        guard let limit else { return sourceTime }
        guard sourceTime + frameDuration > nextTime + 0.000001 else { return nil }
        let time = max(sourceTime, nextTime)
        nextTime = time + 1 / limit
        return time
    }
}

// AVAssetReader 只在串行队列访问；主线程只取已完成的画面，不等待解码。
final class StreamingAnimation: @unchecked Sendable {
    let capacity: Int
    let resolution: Int
    struct Entry { let index: Int; let time: Double; let frame: Frame }
    struct Startup {
        let frames: Int
        let seconds: Double
        let reused: Int
    }
    static let startupSeconds = 0.25
    private let queue = DispatchQueue(label: "bailong.animation.stream", qos: .userInitiated)
    private let lock = NSLock()
    private let asset: AVAsset
    private let track: AVAssetTrack
    private let converter: CPUFrameConverter
    private let onFailure: (Error) -> Void
    private let onFramesReady: (StreamingAnimation) -> Void
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var nextIndex = 0
    private var referenceBounds = CGRect.zero
    private var buffered = [Entry]()
    private var displayed: Entry?
    private var requestedTime = 0.0
    private var epoch = 0
    private var readerEpoch = 0
    private var displayedEpoch = 0
    private var pumping = false
    private var stopped = false
    private var ended = false
    private var totalFrames: Int
    private let startTime: Double
    private let sourceFPS: Double
    private var samplingFPS: Double?
    private var sampler = AnimationFrameSampler()
    private var decodedSamples = 0, convertedFrames = 0, skippedSamples = 0
    private var underflows = 0, longestUnderflow = 0.0
    private var underflowBegan: Double?
    private var awaitingFrame = false
    private var expiredFrames = 0
    private var replayPrefix: (lastIndex: Int, samplingFPS: Double?)?
    private var reusedOpeningFrames = 0
    private var replayedSamples = 0
    private var continuedBeforeUnderflow: Bool?
    private(set) var startup: Startup?
    private(set) var firstFramePreparedAt: Double?
    init(asset: AVAsset, track: AVAssetTrack, capacity: Int, resolution: Int, frameCount: Int, startTime: Double,
         sourceFPS: Double, fpsLimit: Double?, playbackRate: Double,
         onFramesReady: @escaping (StreamingAnimation) -> Void, onFailure: @escaping (Error) -> Void) {
        self.asset = asset; self.track = track; converter = CPUFrameConverter(resolution: resolution); totalFrames = frameCount
        self.startTime = startTime; self.onFailure = onFailure
        self.capacity = capacity; self.resolution = resolution
        self.sourceFPS = sourceFPS
        self.onFramesReady = onFramesReady
        setPlaybackRate(playbackRate, fpsLimit: fpsLimit)
    }
    var frameCount: Int { lock.withLock { totalFrames } }
    var current: (frame: Frame, index: Int)? { lock.withLock { displayed.map { ($0.frame, $0.index) } } }
    var nextFrameTime: Double? { lock.withLock { buffered.first?.time } }
    func retainedFrames(first: Frame?) -> [Frame] {
        lock.withLock {
            var frames = (buffered + (displayed.map { [$0] } ?? [])).map { $0.frame }
            if let first, !frames.contains(where: { $0.image === first.image }) { frames.append(first) }
            return frames
        }
    }
    func statistics() -> (buffered: Int, underflows: Int, longestUnderflow: Double, decoded: Int, converted: Int, skipped: Int, replayed: Int, expired: Int, continued: Bool?) {
        lock.withLock {
            let ongoing = underflowBegan.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
            return (buffered.count, underflows, max(longestUnderflow, ongoing), decodedSamples,
                    convertedFrames, skippedSamples, replayedSamples, expiredFrames, continuedBeforeUnderflow)
        }
    }
    func setPlaybackRate(_ rate: Double, fpsLimit: Double?) {
        lock.withLock { samplingFPS = fpsLimit.flatMap { $0 < sourceFPS * rate ? $0 / rate : nil } }
    }
    func pauseObservation() { lock.withLock { finishUnderflow() } }
    // 在后台 load 任务中预备首帧，之后所有 reader 操作转交串行队列。
    func prime() throws -> Frame {
        try openReader()
        guard let first = try readFrame() else { throw PetFailure(message: "流式动画没有可播放的帧。") }
        firstFramePreparedAt = ProcessInfo.processInfo.systemUptime
        lock.withLock { displayed = first }
        return first.frame
    }
    // 起播只准备约四分之一秒；交接后用原队列上限补充。此时尚未发布给播放队列。
    func prepareForPlayback(playbackRate: Double, opening: [Entry], isCurrent: () -> Bool) throws -> Frame? {
        var prepared = false
        defer {
            if !prepared { reader?.cancelReading(); reader = nil; output = nil }
        }
        guard isCurrent() else { return nil }
        let first: Frame
        if let cached = opening.first, let last = opening.last {
            displayed = cached; buffered = Array(opening.dropFirst())
            referenceBounds = cached.frame.bounds
            reusedOpeningFrames = opening.count
            replayPrefix = (last.index,samplingFPS)
            firstFramePreparedAt = ProcessInfo.processInfo.systemUptime
            first = cached.frame
        } else { first = try prime() }
        let start = displayed!.time
        let interval = 1 / (samplingFPS ?? sourceFPS)
        func readySeconds() -> Double { ((buffered.last?.time ?? start) - start + interval) / playbackRate }
        while buffered.count < capacity && readySeconds() + 0.000001 < Self.startupSeconds {
            guard isCurrent() else { return nil }
            if reader == nil { try openReader() }
            guard let entry = try readFrame() else {
                ended = true; totalFrames = nextIndex
                recordContinuation()
                break
            }
            buffered.append(entry)
            recordContinuation()
        }
        guard isCurrent() else { return nil }
        startup = Startup(frames:buffered.count+1,seconds:readySeconds(),reused:reusedOpeningFrames)
        prepared = true
        return first
    }
    // 仅在加载完成、发布前读取；保留的是原像素引用。
    func openingFrames(limit: Int) -> [Entry] { Array(([displayed!] + buffered).prefix(limit)) }
    // 后台整段预加载复用同一透明图像转换；尚未发布给串行流队列。
    func preload(isCurrent: () -> Bool, progress: (Int) -> Void) throws -> [Frame]? {
        try openReader()
        defer { reader?.cancelReading(); reader = nil; output = nil }
        var frames = [Frame]()
        while isCurrent() {
            // 整段预加载保留全部源帧，运行中改帧率和速度无需重新加载。
            guard let entry = try readFrame(filterFrames: false) else { return frames }
            if frames.isEmpty { firstFramePreparedAt = ProcessInfo.processInfo.systemUptime }
            frames.append(entry.frame)
            if frames.count == 1 || frames.count % 12 == 0 { progress(frames.count) }
        }
        return nil
    }
    func request(_ time: Double) {
        let schedule = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            if time < requestedTime { finishUnderflow(); epoch += 1; buffered.removeAll(); ended = false }
            requestedTime = time
            let consumed = consume()
            if consumed > 1 { expiredFrames += consumed - 1 }
            awaitingFrame = !ended && buffered.isEmpty
            if !ended, buffered.isEmpty, let displayed,
               displayedEpoch != epoch || time >= displayed.time + 1 / (samplingFPS ?? sourceFPS) - 0.000001,
               underflowBegan == nil {
                underflowBegan = ProcessInfo.processInfo.systemUptime; underflows += 1
            }
            guard !pumping, !ended, buffered.count < capacity else { return false }
            pumping = true; return true
        }
        if schedule { queue.async { [self] in pump() } }
    }
    func stop() {
        lock.withLock { finishUnderflow(); stopped = true; buffered.removeAll() }
        queue.async { [self] in reader?.cancelReading(); reader = nil; output = nil }
    }
    func waitUntilStopped() { queue.sync {} }
    @discardableResult private func consume() -> Int {
        var count = 0
        // 绝对期限转回源时间轴有浮点误差，1µs 内视为同一到期时刻。
        while let first = buffered.first, first.time <= requestedTime + 0.000001 {
            finishUnderflow()
            displayed = first; displayedEpoch = epoch; buffered.removeFirst()
            count += 1
        }
        return count
    }
    // 调用方持有 lock；隐藏、循环和停止不把静止时间记入缺帧等待。
    private func finishUnderflow() {
        if let began = underflowBegan {
            longestUnderflow = max(longestUnderflow, ProcessInfo.processInfo.systemUptime - began)
            underflowBegan = nil
        }
    }
    private func openReader() throws {
        reader?.cancelReading()
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false; reader.add(output)
        guard reader.startReading() else { throw reader.error ?? PetFailure(message: "无法开始流式解码。") }
        self.reader = reader; self.output = output; nextIndex = 0; sampler = AnimationFrameSampler()
    }
    private func pump() {
        do {
            while true {
                let token = lock.withLock { () -> Int? in
                    consume()
                    guard !stopped, !ended, buffered.count < capacity else { pumping = false; return nil }
                    return epoch
                }
                guard let token else { return }
                if readerEpoch != token { replayPrefix = nil; try openReader(); readerEpoch = token }
                else if reader == nil { try openReader() }
                let entry = try readFrame()
                let notify = lock.withLock { () -> Bool in
                    guard !stopped, token == epoch else { return false }
                    recordContinuation()
                    if let entry { buffered.append(entry); consume() }
                    else { finishUnderflow(); ended = true; totalFrames = nextIndex }
                    guard awaitingFrame else { return false }
                    awaitingFrame = false
                    return true
                }
                // 仅空队列恢复时通知一次；常规供帧由时间戳调度，不逐帧派发主线程任务。
                if notify { DispatchQueue.main.async { self.onFramesReady(self) } }
            }
        } catch {
            let report = lock.withLock { () -> Bool in
                pumping = false
                guard !stopped else { return false }
                finishUnderflow(); stopped = true; buffered.removeAll(); return true
            }
            reader?.cancelReading(); reader = nil; output = nil
            if report { DispatchQueue.main.async { self.onFailure(error) } }
        }
    }
    // 发布后由持锁调用方记录；起播阶段尚未与播放队列共享。
    private func recordContinuation() {
        if reusedOpeningFrames > 0, continuedBeforeUnderflow == nil { continuedBeforeUnderflow = underflows == 0 }
    }
    private func readFrame(filterFrames: Bool = true) throws -> Entry? {
        while true {
            var reachedEnd = false
            let entry: Entry? = try autoreleasepool {
                guard let sample = output?.copyNextSampleBuffer() else {
                    guard reader?.status == .completed else { throw reader?.error ?? PetFailure(message: "流式视频读取中断。") }
                    reachedEnd = true
                    return nil
                }
                let index = nextIndex; nextIndex += 1
                let sourceTime = max(0, CMSampleBufferGetPresentationTimeStamp(sample).seconds - startTime)
                let limit = lock.withLock { () -> Double? in decodedSamples += 1; return samplingFPS }
                if let prefix = replayPrefix, index <= prefix.lastIndex {
                    // 保持缓存区间原采样相位；只读取 HEVC 依赖样本，不再转换已缓存的像素。
                    _ = sampler.presentationTime(sourceTime:sourceTime,frameDuration:1/sourceFPS,limit:prefix.samplingFPS)
                    lock.withLock { replayedSamples += 1 }
                    return nil
                }
                replayPrefix = nil
                guard let time = sampler.presentationTime(sourceTime: sourceTime, frameDuration: 1 / sourceFPS,
                                                          limit: filterFrames ? limit : nil) else {
                    lock.withLock { skippedSamples += 1 }; return nil
                }
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw PetFailure(message: "流式视频帧缺少像素数据。") }
                let frame = try converter.frame(from: buffer, bounds: index == 0 ? nil : referenceBounds)
                if index == 0 { referenceBounds = frame.bounds }
                lock.withLock { convertedFrames += 1 }
                return Entry(index: index, time: time, frame: frame)
            }
            if reachedEnd || entry != nil { return entry }
            if lock.withLock({ stopped }) { return nil }
        }
    }
}
