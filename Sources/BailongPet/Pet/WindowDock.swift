import AppKit

struct WindowDockTarget {
    struct Identity: Equatable {
        let number: CGWindowID
        let owner: pid_t
    }

    let identity: Identity
    let frame: CGRect

    static func snapshot(through number: CGWindowID = kCGNullWindowID) -> [[String:Any]]? {
        let options: CGWindowListOption = number == kCGNullWindowID
            ? [.optionOnScreenOnly,.excludeDesktopElements]
            : [.optionOnScreenAboveWindow,.optionIncludingWindow,.excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options,number) as? [[String:Any]]
    }

    static func visibleWindows(in snapshot: [[String:Any]]) -> [Self] {
        snapshot.compactMap { item in
            guard item[kCGWindowIsOnscreen as String] as? Bool == true,
                  item[kCGWindowLayer as String] as? Int == 0,
                  let alpha = item[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let pid = item[kCGWindowOwnerPID as String] as? pid_t,
                  let number = item[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = item[kCGWindowBounds as String] as? [String:Any],
                  let frame = CGRect(dictionaryRepresentation:bounds as CFDictionary), !frame.isEmpty else {return nil}
            return Self(identity:Identity(number:number,owner:pid),frame:frame)
        }
    }
}

struct WindowDock {
    let target: WindowDockTarget.Identity
    let edge: BubblePlacement.Side
    let offset: CGFloat
    var outline: CGRect
    var targetFrame: CGRect
    var destination: CGPoint

    private static let snapDistance: CGFloat = 24

    static func transform(edge: BubblePlacement.Side, reference: CGRect, size: CGFloat,
                          exposure: CGFloat, progress: CGFloat) -> CGAffineTransform {
        switch edge {
        case .left,.right:
            // 角色留在目标窗口外侧，把图像裁到紧贴目标的画布边缘。
            return SideDockGeometry.transform(reference:reference,size:size,exposure:exposure,
                                              progress:progress,left:edge == .right)
        case .above:
            return .identity
        case .below:
            if progress == 1 {return CGAffineTransform(a:-1,b:0,c:0,d:-1,tx:size,ty:size)}
            let center = size/2
            return CGAffineTransform(translationX:center,y:center).rotated(by:.pi*progress).translatedBy(x:-center,y:-center)
        }
    }

    static func nearest(to pet: CGRect, cursor: CGPoint, windows: [WindowDockTarget], areas: [CGRect],
                        outlines: [BubblePlacement.Side:CGRect], size: CGFloat) -> Self? {
        var nearest: Self?
        var nearestDistance = snapDistance.nextUp
        for (index,target) in windows.enumerated() {
            for edge in BubblePlacement.Side.allCases {
                guard let outline = outlines[edge] else {continue}
                let frame = target.frame
                let normal = edge.normal(of:frame), tangent = edge.tangent(of:pet.center)
                let cursorTangent = edge.tangent(of:cursor), range = edge.span(of:frame)
                let nearCursor = (range.lowerBound...range.upperBound).contains(cursorTangent)
                    ? abs(edge.normal(of:cursor)-normal) : .infinity
                let nearPet = range.overlaps(edge.span(of:pet)) && edge.isOutside(center:pet.center,normal:normal,tolerance:snapDistance)
                    ? abs(edge.normal(of:pet,opposite:true)-normal) : .infinity
                let distance = min(nearCursor,nearPet)
                guard distance < nearestDistance else {continue}
                let offset = tangent-range.lowerBound
                guard let layout = layout(frame:frame,edge:edge,offset:offset,outline:outline,size:size,areas:areas),
                      !windows[..<index].contains(where:{$0.frame.contains(layout.contact)}) else {continue}
                nearest = Self(target:target.identity,edge:edge,offset:offset,outline:outline,targetFrame:frame,destination:layout.origin)
                nearestDistance = distance
            }
        }
        return nearest
    }

    mutating func follow(_ windows: [WindowDockTarget], areas: [CGRect], size: CGFloat) -> Bool {
        guard let index = windows.firstIndex(where:{$0.identity == target}) else {return false}
        let frame = windows[index].frame
        guard let layout = Self.layout(frame:frame,edge:edge,offset:offset,outline:outline,size:size,areas:areas),
              !windows[..<index].contains(where:{$0.frame.contains(layout.contact)}) else {return false}
        targetFrame = frame; destination = layout.origin
        return true
    }

    private static func layout(frame: CGRect, edge: BubblePlacement.Side, offset: CGFloat, outline: CGRect,
                               size: CGFloat, areas: [CGRect]) -> (origin: CGPoint, contact: CGPoint)? {
        guard !outline.isEmpty else {return nil}
        let windowSpan = edge.span(of:frame), outlineSpan = edge.span(of:outline)
        let half = (outlineSpan.upperBound-outlineSpan.lowerBound)/2
        let preferred = windowSpan.lowerBound+offset
        let normal = edge.normal(of:frame)
        let normalOrigin: CGFloat
        switch edge {
        case .left: normalOrigin = normal-size
        case .right: normalOrigin = normal
        case .above: normalOrigin = normal-outline.maxY
        case .below: normalOrigin = normal-outline.minY
        }
        var closest: (origin: CGPoint, contact: CGPoint)?
        var smallestShift = CGFloat.infinity
        for area in areas {
            let areaSpan = edge.span(of:area)
            let lower = max(windowSpan.lowerBound,areaSpan.lowerBound)+half
            let upper = min(windowSpan.upperBound,areaSpan.upperBound)-half
            guard lower <= upper else {continue}
            let tangent = min(max(preferred,lower),upper)
            let shift = abs(tangent-preferred)
            guard shift < smallestShift else {continue}
            let origin = edge.point(normal:normalOrigin,tangent:tangent-outlineSpan.lowerBound-half)
            guard area.contains(outline.offsetBy(dx:origin.x,dy:origin.y)) else {continue}
            // 检查贴点内侧，避开窗口边界浮点舍入和相邻平铺窗口。
            let contact = edge.point(normal:normal+(edge.isMinimum ? 1 : -1),tangent:tangent)
            closest = (origin,contact); smallestShift = shift
        }
        return closest
    }
}

private extension BubblePlacement.Side {
    var isSide: Bool {self == .left || self == .right}
    var isMinimum: Bool {self == .left || self == .above}

    func normal(of point: CGPoint) -> CGFloat {isSide ? point.x : point.y}
    func tangent(of point: CGPoint) -> CGFloat {isSide ? point.y : point.x}
    func point(normal: CGFloat, tangent: CGFloat) -> CGPoint {
        isSide ? CGPoint(x:normal,y:tangent) : CGPoint(x:tangent,y:normal)
    }
    func span(of frame: CGRect) -> ClosedRange<CGFloat> {isSide ? frame.minY...frame.maxY : frame.minX...frame.maxX}
    func normal(of frame: CGRect, opposite: Bool = false) -> CGFloat {
        normal(of: isMinimum != opposite ? frame.origin : CGPoint(x:frame.maxX,y:frame.maxY))
    }
    func isOutside(center: CGPoint, normal: CGFloat, tolerance: CGFloat) -> Bool {
        let distance = self.normal(of:center)-normal
        return isMinimum ? distance <= tolerance : distance >= -tolerance
    }
}
