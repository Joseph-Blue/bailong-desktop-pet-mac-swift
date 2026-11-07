import AVFoundation

// AVAssetReader 只在串行队列访问；主线程只取已完成的画面，不等待解码。
final class StreamingAnimation: @unchecked Sendable {
    let capacity: Int
    let resolution: Int
    private struct Entry { let index: Int; let time: Double; let frame: Frame }
    private let queue = DispatchQueue(label: "bailong.animation.stream", qos: .userInitiated)
    private let lock = NSLock()
    private let asset: AVAsset
    private let track: AVAssetTrack
    private let converter: CPUFrameConverter
    private let onFailure: (Error) -> Void
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var nextIndex = 0
    private var referenceBounds = CGRect.zero
    private var buffered = [Entry]()
    private var displayed: Entry?
    private var requestedTime = 0.0
    private var epoch = 0
    private var readerEpoch = 0
    private var pumping = false
    private var stopped = false
    private var ended = false
    private var totalFrames: Int
    private let startTime: Double
    init(asset: AVAsset, track: AVAssetTrack, capacity: Int, resolution: Int, frameCount: Int, startTime: Double, onFailure: @escaping (Error) -> Void) {
        self.asset = asset; self.track = track; converter = CPUFrameConverter(resolution: resolution); totalFrames = frameCount
        self.startTime = startTime; self.onFailure = onFailure
        self.capacity = capacity; self.resolution = resolution
    }
    var frameCount: Int { lock.withLock { totalFrames } }
    var current: (frame: Frame, index: Int)? { lock.withLock { displayed.map { ($0.frame, $0.index) } } }
    func statistics(retaining first: Frame? = nil) -> (frames: Int, bytes: Int, buffered: Int) {
        lock.withLock {
            var frames = (buffered + (displayed.map { [$0] } ?? [])).map { $0.frame }
            if let first, !frames.contains(where: { $0.image === first.image }) { frames.append(first) }
            return (frames.count, frames.reduce(0) { $0 + $1.cost }, buffered.count)
        }
    }
    // 在后台 load 任务中预备首帧，之后所有 reader 操作转交串行队列。
    func prime() throws -> Frame {
        try openReader()
        guard let first = try readFrame() else { throw PetFailure(message: "流式动画没有可播放的帧。") }
        lock.withLock { displayed = first }
        return first.frame
    }
    // 后台整段预加载复用同一透明图像转换；尚未发布给串行流队列。
    func preload(isCurrent: () -> Bool, progress: (Int) -> Void) throws -> [Frame]? {
        try openReader()
        defer { reader?.cancelReading(); reader = nil; output = nil }
        var frames = [Frame]()
        while isCurrent() {
            guard let entry = try readFrame() else { return frames }
            frames.append(entry.frame)
            if frames.count == 1 || frames.count % 12 == 0 { progress(frames.count) }
        }
        return nil
    }
    func request(_ time: Double) {
        let schedule = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            if time < requestedTime { epoch += 1; buffered.removeAll(); ended = false }
            requestedTime = time
            consume()
            guard !pumping, !ended, buffered.count < capacity else { return false }
            pumping = true; return true
        }
        if schedule { queue.async { [self] in pump() } }
    }
    func stop() {
        lock.withLock { stopped = true; buffered.removeAll() }
        queue.async { [self] in reader?.cancelReading(); reader = nil; output = nil }
    }
    func waitUntilStopped() { queue.sync {} }
    private func consume() {
        while let first = buffered.first, first.time <= requestedTime {
            displayed = first; buffered.removeFirst()
        }
    }
    private func openReader() throws {
        reader?.cancelReading()
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false; reader.add(output)
        guard reader.startReading() else { throw reader.error ?? PetFailure(message: "无法开始流式解码。") }
        self.reader = reader; self.output = output; nextIndex = 0
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
                if readerEpoch != token { try openReader(); readerEpoch = token }
                let entry = try readFrame()
                lock.withLock {
                    guard !stopped, token == epoch else { return }
                    if let entry { buffered.append(entry); consume() }
                    else { ended = true; totalFrames = nextIndex }
                }
            }
        } catch {
            let report = lock.withLock { () -> Bool in
                pumping = false
                guard !stopped else { return false }
                stopped = true; buffered.removeAll(); return true
            }
            reader?.cancelReading(); reader = nil; output = nil
            if report { DispatchQueue.main.async { self.onFailure(error) } }
        }
    }
    private func readFrame() throws -> Entry? {
        try autoreleasepool {
            guard let sample = output?.copyNextSampleBuffer() else {
                guard reader?.status == .completed else { throw reader?.error ?? PetFailure(message: "流式视频读取中断。") }
                return nil
            }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw PetFailure(message: "流式视频帧缺少像素数据。") }
            let frame = try converter.frame(from: buffer, bounds: nextIndex == 0 ? nil : referenceBounds)
            if nextIndex == 0 { referenceBounds = frame.bounds }
            let entry = Entry(index: nextIndex, time: max(0, CMSampleBufferGetPresentationTimeStamp(sample).seconds - startTime), frame: frame)
            nextIndex += 1
            return entry
        }
    }
}
