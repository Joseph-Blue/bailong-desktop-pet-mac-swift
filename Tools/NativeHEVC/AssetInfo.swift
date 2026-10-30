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

// 这是构建工具，不随桌宠运行。FFmpeg 只用于读取原 WebM 和调用系统编码器。
@main
struct PrepareNativeSamples {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 4 else {
                throw NativeFailure(message: "用法：PrepareNativeSamples <素材目录> <ffmpeg> <输出目录>")
            }
            let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let encoder = URL(fileURLWithPath: CommandLine.arguments[2])
            let destination = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
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
            var samples = [NativeSample]()
            for (key, name) in [("idle", "待机"), ("dragAnimation", "拖拽"), ("landingAnimation", "落地")] {
                guard let clip = catalog[key] as? [String: Any], let id = clip["id"] as? String,
                      let path = (clip["playbackFile"] ?? clip["file"]) as? String else {
                    throw NativeFailure(message: "素材清单缺少 \(key) 的 id 或文件路径")
                }
                let output = staging.appendingPathComponent(id + ".mov")
                let task = Process()
                task.executableURL = encoder
                // 保持原尺寸和时间戳；BGRA 与 alpha_quality 显式启用透明 HEVC。
                // 软件编码是明确允许的系统能力，不承诺本机或 Intel 全程硬件加速。
                task.arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n",
                    "-c:v", "libvpx-vp9", "-threads", "2", "-i", source.appendingPathComponent(path).path,
                    "-map", "0:v:0", "-an", "-pix_fmt", "bgra", "-fps_mode", "passthrough",
                    "-c:v", "hevc_videotoolbox", "-allow_sw", "1", "-alpha_quality", "1",
                    "-b:v", "8M", "-tag:v", "hvc1", "-movflags", "+faststart", output.path]
                print("转码：\(name) → \(output.lastPathComponent)")
                try task.run()
                task.waitUntilExit()
                guard task.terminationStatus == 0 else {
                    throw NativeFailure(message: "\(id) 转码失败，退出码 \(task.terminationStatus)；未完成输出保留在 \(staging.path)")
                }
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
                samples.append(NativeSample(id: id, name: name, file: output.lastPathComponent,
                    sourceFile: path, durationSeconds: duration.seconds, width: Int(size.width),
                    height: Int(size.height), frameRate: rate, containsAlpha: true))
                print("已生成：\(id)，\(Int(size.width))×\(Int(size.height))，\(rate) fps，\(duration.seconds) 秒，含 alpha")
            }
            let json = JSONEncoder()
            json.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try json.encode(NativeSamples(version: "0.3.0-dev.1", samples: samples))
                .write(to: staging.appendingPathComponent("samples.json"), options: .atomic)
            try manager.moveItem(at: staging, to: destination)
            print("素材准备完成：\(destination.path)")
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
