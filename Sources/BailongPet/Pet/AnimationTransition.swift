import CoreGraphics

// 只在动作交接时取样现有 Alpha；包含素材校准，不复制整张图像或逐帧比较。
enum AnimationTransition {
    static let duration = 0.18
    static let minimumOverlap = 0.90

    static func rect(for clip: Clip) -> CGRect {
        let scale = clip.renderScale ?? 1, offset = clip.renderOffset ?? [0, 0]
        return CGRect(x: (1 - scale) / 2 + offset[0], y: 1 - scale + offset[1], width: scale, height: scale)
    }

    static func overlap(_ previous: Frame, clip: Clip, _ next: Frame, nextClip: Clip) -> Double {
        let oldRect = rect(for: clip), newRect = rect(for: nextClip)
        let area = oldRect.union(newRect)
        func alpha(_ frame: Frame, rect: CGRect, point: CGPoint) -> Int {
            guard rect.contains(point) else { return 0 }
            return Int(frame.alpha(x: Int((point.x - rect.minX) / rect.width * 512),
                                   y: Int((point.y - rect.minY) / rect.height * 512)))
        }
        var intersection = 0, union = 0
        for y in 0..<64 { for x in 0..<64 {
            let point = CGPoint(x: area.minX + (Double(x) + 0.5) / 64 * area.width,
                                y: area.minY + (Double(y) + 0.5) / 64 * area.height)
            let a = alpha(previous, rect: oldRect, point: point), b = alpha(next, rect: newRect, point: point)
            intersection += min(a, b); union += max(a, b)
        } }
        return union == 0 ? 0 : Double(intersection) / Double(union)
    }
}
