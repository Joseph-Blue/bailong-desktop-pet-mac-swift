import Accelerate
import CoreVideo
import Foundation

// 仅由所属 StreamingAnimation 的解码队列使用。工作区复用，发布的 CGImage 独占像素内存。
final class CPUFrameConverter {
    private final class Workspace {
        private(set) var pointer: UnsafeMutableRawPointer?
        private var capacity = 0
        func reserve(_ size: Int) throws -> UnsafeMutableRawPointer? {
            if size > capacity {
                guard let next = malloc(size) else { throw PetFailure(message: "无法分配动画处理缓冲。") }
                free(pointer); pointer = next; capacity = size
            }
            return pointer
        }
        deinit { free(pointer) }
    }

    private let resolution: Int
    private let cleanIsolatedPixels: Bool
    private let outputSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let outputInfo = CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
    private let linear = Workspace(), scaled = Workspace(), scaleWork = Workspace(), conversionWork = Workspace()
    private let linearSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    private var sourceSpace: CGColorSpace?
    private var converter: vImageConverter?
    private var toLinear: vImageConverter?
    private var fromLinear: vImageConverter?
    private var sourcePremultiplied = false
    private var sourceResizing = false
    private let flags = vImage_Flags(kvImageDoNotTile)

    init(resolution: Int, cleanIsolatedPixels: Bool = false) {
        self.resolution = resolution; self.cleanIsolatedPixels = cleanIsolatedPixels
    }

    func frame(from buffer: CVPixelBuffer, bounds: CGRect?) throws -> Frame {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              let colorSpace = CVImageBufferGetColorSpace(buffer)?.takeUnretainedValue(),
              let alphaMode = CVBufferCopyAttachment(buffer, kCVImageBufferAlphaChannelModeKey, nil) else {
            throw PetFailure(message: "动画帧缺少 BGRA 颜色或透明度信息。")
        }
        let premultiplied = CFEqual(alphaMode, kCVImageBufferAlphaChannelMode_PremultipliedAlpha)
        guard premultiplied || CFEqual(alphaMode, kCVImageBufferAlphaChannelMode_StraightAlpha) else {
            throw PetFailure(message: "动画帧的透明度格式不受支持。")
        }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let resizing = width != resolution || height != resolution
        try prepareConverter(colorSpace, premultiplied: premultiplied, resizing: resizing)
        try check(CVPixelBufferLockBaseAddress(buffer, .readOnly), "读取动画像素")
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw PetFailure(message: "动画帧没有像素数据。") }
        var input = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        let rowBytes = resolution * 4, byteCount = rowBytes * resolution
        if resizing {
            // 与原 Core Image 链一致：先转线性光、预乘 Alpha，再缩放，最后转回 sRGB。
            // 浮点工作区跨帧复用，避免在视频编码的非线性 RGB 上直接插值导致色调变化。
            var source = vImage_Buffer(data: try linear.reserve(width * height * 16), height: input.height, width: input.width, rowBytes: width * 16)
            try convert(toLinear!, input: &input, output: &source)
            var destination = vImage_Buffer(data: try scaled.reserve(resolution * resolution * 16), height: vImagePixelCount(resolution), width: vImagePixelCount(resolution), rowBytes: resolution * 16)
            let scalingFlags = flags | vImage_Flags(kvImageHighQualityResampling)
            let size = vImageScale_ARGBFFFF(&source, &destination, nil, scalingFlags | vImage_Flags(kvImageGetTempBufferSize))
            guard size >= 0 else { throw failure("准备动画缩放", size) }
            try check(vImageScale_ARGBFFFF(&source, &destination, try scaleWork.reserve(size), scalingFlags), "缩放动画")
            // Lanczos 在边缘会过冲；恢复合法预乘范围再交给颜色转换。
            let samples = destination.data.assumingMemoryBound(to: Float.self)
            for i in stride(from: 0, to: resolution * resolution * 4, by: 4) {
                let alpha = min(1, max(0, samples[i + 3])); samples[i + 3] = alpha
                for channel in 0..<3 { samples[i + channel] = min(alpha, max(0, samples[i + channel])) }
            }
            input = destination
        }
        guard let pixels = malloc(byteCount) else { throw PetFailure(message: "无法分配动画画面。") }
        // Provider 接管内存后仅在最后一个 CGImage 引用释放时回收，不复用正在显示的帧。
        guard let provider = CGDataProvider(dataInfo: nil, data: pixels, size: byteCount, releaseData: { _, data, _ in
            free(UnsafeMutableRawPointer(mutating: data))
        }) else { free(pixels); throw PetFailure(message: "无法创建动画像素源。") }
        var output = vImage_Buffer(data: pixels, height: vImagePixelCount(resolution), width: vImagePixelCount(resolution), rowBytes: rowBytes)
        try convert(resizing ? fromLinear! : converter!, input: &input, output: &output)
        if cleanIsolatedPixels {
            IsolatedPixelCleanup.apply(to: pixels.assumingMemoryBound(to: UInt8.self),
                                       width: resolution, height: resolution, rowBytes: rowBytes)
        }
        guard let image = CGImage(width: resolution, height: resolution, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: rowBytes, space: outputSpace, bitmapInfo: outputInfo,
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw PetFailure(message: "无法创建动画画面。")
        }
        // 从刚写好的 CPU 像素提取命中遮罩，不再经 CGDataProviderCopyData 复制整张 RGBA。
        var alpha = Data(count: resolution * resolution)
        var x0 = resolution, y0 = resolution, x1 = -1, y1 = -1
        let source = pixels.assumingMemoryBound(to: UInt8.self)
        alpha.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            for y in 0..<resolution { for x in 0..<resolution {
                let value = source[y * rowBytes + x * 4 + 3]
                destination[y * resolution + x] = value
                if bounds == nil && value > 0 { x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y) }
            } }
        }
        let scale = 512.0 / Double(resolution)
        let visible = bounds ?? (x1 < 0 ? .zero : CGRect(x: Double(x0) * scale, y: Double(y0) * scale,
            width: Double(x1 - x0 + 1) * scale, height: Double(y1 - y0 + 1) * scale))
        return Frame(image: image, pixels: alpha, bounds: visible, alphaOnly: true)
    }

    private func prepareConverter(_ colorSpace: CGColorSpace, premultiplied: Bool, resizing: Bool) throws {
        if let sourceSpace, CFEqual(sourceSpace, colorSpace), sourcePremultiplied == premultiplied, sourceResizing == resizing { return }
        var input = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: Unmanaged.passUnretained(colorSpace),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: (premultiplied ? CGImageAlphaInfo.premultipliedFirst : .first).rawValue)), version: 0, decode: nil, renderingIntent: .defaultIntent)
        var output = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: Unmanaged.passUnretained(outputSpace),
            bitmapInfo: outputInfo, version: 0, decode: nil, renderingIntent: .defaultIntent)
        var floating = vImage_CGImageFormat(bitsPerComponent: 32, bitsPerPixel: 128, colorSpace: Unmanaged.passUnretained(linearSpace),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.union(.floatComponents).union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)), version: 0, decode: nil, renderingIntent: .defaultIntent)
        converter = resizing ? nil : try makeConverter(&input, &output)
        toLinear = resizing ? try makeConverter(&input, &floating) : nil
        fromLinear = resizing ? try makeConverter(&floating, &output) : nil
        sourceSpace = colorSpace; sourcePremultiplied = premultiplied; sourceResizing = resizing
    }
    private func makeConverter(_ input: inout vImage_CGImageFormat, _ output: inout vImage_CGImageFormat) throws -> vImageConverter {
        var error: vImage_Error = 0
        guard let next = vImageConverter_CreateWithCGImageFormat(&input, &output, nil, flags, &error)?.takeRetainedValue() else {
            throw failure("创建动画颜色转换", error)
        }
        return next
    }
    private func convert(_ converter: vImageConverter, input: inout vImage_Buffer, output: inout vImage_Buffer) throws {
        let size = vImageConvert_AnyToAny(converter, &input, &output, nil, flags | vImage_Flags(kvImageGetTempBufferSize))
        guard size >= 0 else { throw failure("准备动画颜色转换", size) }
        try check(vImageConvert_AnyToAny(converter, &input, &output, try conversionWork.reserve(size), flags), "转换动画颜色")
    }
    private func check<T: BinaryInteger>(_ error: T, _ operation: String) throws {
        if error != 0 { throw failure(operation, error) }
    }
    private func failure<T: BinaryInteger>(_ operation: String, _ error: T) -> PetFailure {
        PetFailure(message: "\(operation)失败（\(error)）。")
    }
}
