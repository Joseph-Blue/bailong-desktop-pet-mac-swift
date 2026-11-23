import CoreGraphics

enum SideDockGeometry {
    static func originX(frame:CGRect,visibleFrame:CGRect,size:CGFloat,left:Bool) -> CGFloat {
        // 系统给侧边 Dock 留有额外间距，让桌宠在 Dock 下方覆盖这条缝。
        let overlap:CGFloat = 2
        return left ? max(frame.minX,visibleFrame.minX-overlap) : min(frame.maxX,visibleFrame.maxX+overlap)-size
    }

    static func transform(reference:CGRect,size:CGFloat,exposure:CGFloat,progress:CGFloat,left:Bool) -> CGAffineTransform {
        let center = size/2
        let rotation = CGAffineTransform(translationX:center,y:center)
            .rotated(by:(left ? 1 : -1) * .pi/4 * progress).translatedBy(x:-center,y:-center)
        let bounds = reference.applying(rotation)
        let visible = (1-(1-exposure)*progress)*bounds.width
        let shift = left ? visible-bounds.maxX : size-visible-bounds.minX
        return rotation.concatenating(CGAffineTransform(translationX:shift*progress,y:0))
    }

    // 只采样默认待机首帧，让气泡跟随轮廓而不随播放帧跳动。
    struct Outline {
        private static let resolution = 128
        private let samples:[CGPoint]

        init(frame:Frame,rect:CGRect) {
            let resolution = Self.resolution
            var samples = [CGPoint]()
            for y in 0..<resolution { for x in 0..<resolution {
                let u = (CGFloat(x)+0.5)/CGFloat(resolution), v = (CGFloat(y)+0.5)/CGFloat(resolution)
                if frame.alpha(x:Int(u*512),y:Int(v*512)) > 16 {
                    samples.append(CGPoint(x:rect.minX+u*rect.width,y:rect.minY+v*rect.height))
                }
            } }
            self.samples = samples
        }

        func dockedBounds(transform:CGAffineTransform) -> CGRect {
            let canvas = CGRect(x:0,y:0,width:1,height:1)
            var bounds = CGRect.null
            for sample in samples {
                let point = sample.applying(transform)
                if canvas.contains(point) {bounds = bounds.union(CGRect(origin:point,size:.zero))}
            }
            return bounds
        }
    }
}
