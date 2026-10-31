import AVFoundation
import Foundation

struct NativeSample: Codable {
    let id: String
    let name: String
    let file: String
    let sourceFile: String
    let durationSeconds: Double
    let width: Int
    let height: Int
    let frameRate: Float
    let containsAlpha: Bool
}

struct NativeSamples: Codable {
    let version: String
    let samples: [NativeSample]
}

struct NativeFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// 这是构建工具，不随桌宠运行。FFmpeg 只生成中间素材，Apple 工具负责透明 HEVC。
@main
struct PrepareNativeSamples {
    static func clips(in value: Any) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            if object["id"] is String, object["file"] is String { return [object] }
            return object.keys.sorted().flatMap { clips(in: object[$0]!) }
        }
        return (value as? [Any] ?? []).flatMap { clips(in: $0) }
    }
    static func nativeCatalog(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            if let id = object["id"] as? String, object["file"] is String {
                object["sourceFile"] = object["playbackFile"] ?? object["file"]
                object["file"] = "透明HEVC/\(id).mov"
                object["playbackFile"] = object["file"]
                return object
            }
            return object.mapValues { nativeCatalog($0) }
        }
        if let array = value as? [Any] { return array.map { nativeCatalog($0) } }
        return value
    }
    static func run(_ executable: URL, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NativeFailure(message: "\(executable.lastPathComponent) 失败，退出码 \(task.terminationStatus)")
        }
    }

    static func main() async {
        do {
            guard [5,6].contains(CommandLine.arguments.count),
                  CommandLine.arguments.count == 5 || CommandLine.arguments[5] == "--catalog" else {
                throw NativeFailure(message: "用法：PrepareNativeSamples <素材目录> <ffmpeg> <输出目录> <版本> [--catalog]")
            }
            let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let encoder = URL(fileURLWithPath: CommandLine.arguments[2])
            let destination = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
            let version = CommandLine.arguments[4]
            let fullCatalog = CommandLine.arguments.count == 6
            let manager = FileManager.default
            // 输出为独立目录；存在时显式报错，避免误覆盖上次 review 的素材。
            guard !manager.fileExists(atPath: destination.path) else {
                throw NativeFailure(message: "输出目录已存在：\(destination.path)；复用请使用 --reuse-assets，重新转码请先移走旧目录。")
            }
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent("素材清单.json")))
            guard let catalog = manifest as? [String: Any] else {
                throw NativeFailure(message: "素材清单不是 JSON 对象")
            }
            // 临时目录完成后才成为可打包目录；转码失败时保留错误，不生成有效清单。
            let staging = destination.deletingLastPathComponent().appendingPathComponent("samples-\(UUID().uuidString).partial")
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            let movieRoot = fullCatalog ? staging.appendingPathComponent("透明HEVC") : staging
            try manager.createDirectory(at: movieRoot, withIntermediateDirectories: true)
            let selected: [[String: Any]]
            if fullCatalog { selected = clips(in: catalog) }
            else {
                selected = try ["idle", "dragAnimation", "landingAnimation"].map { key in
                    guard let clip = catalog[key] as? [String: Any] else {
                        throw NativeFailure(message: "素材清单缺少 \(key)")
                    }
                    return clip
                }
            }
            var samples = [NativeSample]()
            for clip in selected {
                guard let id = clip["id"] as? String,
                      let path = (clip["playbackFile"] ?? clip["file"]) as? String else {
                    throw NativeFailure(message: "素材清单缺少 id 或文件路径")
                }
                let name = clip["name"] as? String ?? id
                let output = movieRoot.appendingPathComponent(id + ".mov")
                let intermediate = staging.appendingPathComponent(id + "-prores4444.mov")
                print("转码：\(name) → \(output.lastPathComponent)")
                // FFmpeg 7.1 直接封装的透明 HEVC 在本机 AVAssetReader 中报 -11801/-12713。
                // 改用带 alpha 的 ProRes 4444 作中间文件，由 Apple 完成 HEVC 编码和封装。
                // 维持原尺寸与时间戳；两次编码不宣称无损，不修饰原素材边缘。
                try run(encoder, ["-hide_banner", "-loglevel", "error", "-nostdin", "-n",
                    "-c:v", "libvpx-vp9", "-threads", "2", "-i", source.appendingPathComponent(path).path,
                    "-map", "0:v:0", "-an", "-c:v", "prores_ks", "-profile:v", "4",
                    "-pix_fmt", "yuva444p10le", "-alpha_bits", "16", "-fps_mode", "passthrough", intermediate.path])
                try run(URL(fileURLWithPath: "/usr/bin/avconvert"), ["--source", intermediate.path,
                    "--preset", "PresetHEVCHighestQualityWithAlpha", "--output", output.path])
                // 用未来运行时所用的框架读取元数据，避免把不带 alpha 的 HEVC 当成成功。
                let asset = AVURLAsset(url: output)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw NativeFailure(message: "\(id) 没有可读取的视频轨道")
                }
                let characteristics = try await track.load(.mediaCharacteristics)
                guard characteristics.contains(.containsAlphaChannel) else {
                    throw NativeFailure(message: "\(id) 的 HEVC 视频没有透明通道")
                }
                let size = try await track.load(.naturalSize)
                let duration = try await asset.load(.duration)
                let rate = try await track.load(.nominalFrameRate)
                guard duration.seconds.isFinite, duration.seconds > 0 else {
                    throw NativeFailure(message: "\(id) 的时长无效")
                }
                // 此次故障中元数据正常而实际解码失败；生成时必须能读到真实首帧。
                let reader = try AVAssetReader(asset: asset)
                let decoded = AVAssetReaderTrackOutput(track: track,
                    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                reader.add(decoded)
                guard reader.startReading(), let frame = decoded.copyNextSampleBuffer(),
                      CMSampleBufferGetImageBuffer(frame) != nil else {
                    throw reader.error ?? NativeFailure(message: "\(id) 无法原生解码首帧")
                }
                reader.cancelReading()
                try manager.removeItem(at: intermediate)
                samples.append(NativeSample(id: id, name: name, file: output.lastPathComponent,
                    sourceFile: path, durationSeconds: duration.seconds, width: Int(size.width),
                    height: Int(size.height), frameRate: rate, containsAlpha: true))
                print("已生成：\(id)，\(Int(size.width))×\(Int(size.height))，\(rate) fps，\(duration.seconds) 秒，含 alpha，原生首帧解码通过")
            }
            let json = JSONEncoder()
            json.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try json.encode(NativeSamples(version: version, samples: samples))
                .write(to: staging.appendingPathComponent("samples.json"), options: .atomic)
            if fullCatalog {
                try JSONSerialization.data(withJSONObject: nativeCatalog(catalog), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    .write(to: staging.appendingPathComponent("素材清单.json"), options: .atomic)
            }
            try manager.moveItem(at: staging, to: destination)
            print("素材准备完成：\(destination.path)")
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
