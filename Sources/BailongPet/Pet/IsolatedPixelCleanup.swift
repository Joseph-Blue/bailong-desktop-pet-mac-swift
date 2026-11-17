import Foundation

// 只删除完全断开的微小低 Alpha 连通块，不侵蚀主体，不改变其余像素的颜色或透明度。
enum IsolatedPixelCleanup {
    @discardableResult
    static func apply(to pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, rowBytes: Int) -> Int {
        let maximumAlpha: UInt8 = 16
        let maximumArea = max(1, Int((4 * pow(Double(width) / 512, 2)).rounded()))
        var component = [Int](); component.reserveCapacity(maximumArea + 1)
        var removed = 0
        for y in 0..<height { for x in 0..<width {
            let start = y * rowBytes + x * 4
            guard pixels[start + 3] > 0, pixels[start + 3] <= maximumAlpha else { continue }
            component.removeAll(keepingCapacity: true); component.append(start)
            var cursor = 0, isolated = true
            search: while cursor < component.count {
                let offset = component[cursor], cy = offset / rowBytes, cx = (offset % rowBytes) / 4
                cursor += 1
                for ny in max(0, cy - 1)...min(height - 1, cy + 1) {
                    for nx in max(0, cx - 1)...min(width - 1, cx + 1) {
                        let neighbor = ny * rowBytes + nx * 4, alpha = pixels[neighbor + 3]
                        guard alpha > 0, !component.contains(neighbor) else { continue }
                        if alpha > maximumAlpha || component.count == maximumArea {
                            isolated = false; break search
                        }
                        component.append(neighbor)
                    }
                }
            }
            if isolated {
                for offset in component { for channel in 0..<4 { pixels[offset + channel] = 0 } }
                removed += component.count
            }
        } }
        return removed
    }
}
