import AVFoundation
import Foundation
import CoreImage

// 离线素材接入工具，不进入应用包，不改变角色动作清单参数。
@main
struct ApplyPNGRepairs {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure(message: "\(executable.lastPathComponent) 失败：\(process.terminationStatus)")
        }
    }
    static func writeProRes(frames: URL, count: Int, output: URL) async throws {
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444,
            AVVideoWidthKey: 720, AVVideoHeightKey: 720
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw Failure(message: "系统不支持 ProRes 4444 素材编码。") }
        writer.add(input)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 720, kCVPixelBufferHeightKey as String: 720,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.startWriting() else { throw writer.error ?? Failure(message: "无法启动原生素材编码。") }
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw Failure(message: "无法创建原生像素缓冲池。") }
        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        for index in 0..<count {
            while writer.status == .writing && !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard writer.status == .writing else { throw writer.error ?? Failure(message: "原生素材编码中断。") }
            try autoreleasepool {
                let file = frames.appendingPathComponent(String(format: "%04d.png", index + 1))
                guard let image = CIImage(contentsOf: file), image.extent.size == CGSize(width: 720, height: 720) else {
                    throw Failure(message: "PNG 必须为 720×720：\(file.path)")
                }
                var buffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
                guard status == kCVReturnSuccess, let buffer else { throw Failure(message: "分配像素缓冲失败：\(status)") }
                context.render(image, to: buffer, bounds: image.extent, colorSpace: colorSpace)
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 24)) else {
                    throw writer.error ?? Failure(message: "写入 PNG 帧失败：\(file.lastPathComponent)")
                }
            }
        }
        writer.endSession(atSourceTime: CMTime(value: Int64(count), timescale: 24))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure(message: "原生素材编码未完成。") }
    }
    static func main() async {
        do {
            guard CommandLine.arguments.count == 5 ||
                    (CommandLine.arguments.count == 6 && CommandLine.arguments[5] == "--landing") else {
                throw Failure(message: "用法：ApplyPNGRepairs <现有素材目录> <修复PNG目录> <新输出目录> <版本> [--landing]")
            }
            let args = CommandLine.arguments
            let catalog = URL(fileURLWithPath: args[1], isDirectory: true)
            let pngRoot = URL(fileURLWithPath: args[2], isDirectory: true)
            let output = URL(fileURLWithPath: args[3], isDirectory: true)
            let manager = FileManager.default
            guard !manager.fileExists(atPath: output.path) else {
                throw Failure(message: "输出已存在：\(output.path)")
            }
            let staging = output.deletingLastPathComponent().appendingPathComponent("png-repairs-\(UUID().uuidString).partial")
            try manager.copyItem(at: catalog, to: staging)
            let landingOnly = args.count == 6
            let repairs = landingOnly
                ? [("landing", "04_落地_landing", 48)]
                : [("idle", "01_待机_idle", 96), ("idle2", "02_第二待机_idle2", 96), ("drag", "03_拖拽_drag", 96)]
            var records = [[String: Any]]()
            for (id, folder, frameCount) in repairs {
                let expectedDuration = Double(frameCount) / 24
                let frames = pngRoot.appendingPathComponent(folder, isDirectory: true)
                let names = try manager.contentsOfDirectory(atPath: frames.path).filter { $0.hasSuffix(".png") }.sorted()
                guard names == (1...frameCount).map({ String(format: "%04d.png", $0) }) else {
                    throw Failure(message: "\(folder) 必须包含从 0001 开始连续编号的 \(frameCount) 张 PNG。")
                }
                let intermediate = staging.appendingPathComponent("\(id)-prores4444.mov")
                let movie = staging.appendingPathComponent("透明HEVC/\(id).mov")
                try manager.removeItem(at: movie)
                print("接入 PNG：\(id)，\(frameCount) 帧 / 24 fps")
                try await writeProRes(frames: frames, count: frameCount, output: intermediate)
                try run(URL(fileURLWithPath: "/usr/bin/avconvert"), ["--source", intermediate.path,
                    "--preset", "PresetHEVCHighestQualityWithAlpha", "--output", movie.path])
                let asset = AVURLAsset(url: movie)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw Failure(message: "\(id) 缺少视频轨道")
                }
                let size = try await track.load(.naturalSize)
                let rate = try await track.load(.nominalFrameRate)
                let duration = try await asset.load(.duration)
                let characteristics = try await track.load(.mediaCharacteristics)
                guard characteristics.contains(.containsAlphaChannel), size.width == 720, size.height == 720,
                      abs(rate - 24) < 0.01, abs(duration.seconds - expectedDuration) < 0.01 else {
                    throw Failure(message: "\(id) 的透明通道、尺寸、帧率或时长不符合原动作")
                }
                let reader = try AVAssetReader(asset: asset)
                let decoded = AVAssetReaderTrackOutput(track: track,
                    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                reader.add(decoded)
                guard reader.startReading(), let sample = decoded.copyNextSampleBuffer(),
                      CMSampleBufferGetImageBuffer(sample) != nil else {
                    throw reader.error ?? Failure(message: "\(id) 无法原生解码首帧")
                }
                reader.cancelReading()
                try manager.removeItem(at: intermediate)
                records.append(["id": id, "sourcePNG": frames.path, "frames": frameCount,
                    "frameRate": rate, "durationSeconds": duration.seconds,
                    "width": Int(size.width), "height": Int(size.height), "containsAlpha": true])
                print("已接入：\(id)，720×720，24 fps，\(expectedDuration) 秒，含 alpha，原生首帧解码通过")
            }
            let report: [String: Any] = ["version": args[4], "source": "去杂色与局部平滑 PNG", "repairs": records]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: staging.appendingPathComponent("applied-png-repairs.json"), options: .atomic)
            let metadataURL = staging.appendingPathComponent("samples.json")
            var metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: metadataURL)) as! [String: Any]
            metadata["version"] = args[4]
            var samples = metadata["samples"] as! [[String: Any]]
            for index in samples.indices {
                if let record = records.first(where: { $0["id"] as? String == samples[index]["id"] as? String }) {
                    samples[index]["sourceFile"] = (record["sourcePNG"] as! String) + "/%04d.png"
                }
            }
            metadata["samples"] = samples
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: metadataURL, options: .atomic)
            try manager.moveItem(at: staging, to: output)
            print("素材接入完成：\(output.path)")
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
