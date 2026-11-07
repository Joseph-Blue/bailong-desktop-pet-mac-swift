import AppKit
import ImageIO
import UniformTypeIdentifiers

// 离线清理模板图：保留原图，去除低 Alpha 残留及孤立杂点，不重绘角色。
guard CommandLine.arguments.count == 3 else {
    fatalError("用法：PrepareStatusIcon 输入.png 输出.png")
}
let input = URL(fileURLWithPath:CommandLine.arguments[1])
let output = URL(fileURLWithPath:CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL,nil),
      let image = CGImageSourceCreateImageAtIndex(source,0,nil) else {
    fatalError("无法读取输入图片")
}
let width = image.width, height = image.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
guard let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,
                              bytesPerRow:width*4,space:colorSpace,bitmapInfo:bitmapInfo),
      let data = context.data?.assumingMemoryBound(to:UInt8.self) else {
    fatalError("无法创建图片画布")
}
context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
var visited = [Bool](repeating:false,count:width*height)
var retained = [Bool](repeating:false,count:width*height)
var components = 0, removed = 0
for start in 0..<(width*height) where !visited[start] && data[start*4+3] >= 8 {
    var pixels = [start], head = 0
    visited[start] = true
    while head < pixels.count {
        let index = pixels[head], x = index % width, y = index / width
        head += 1
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x+dx, ny = y+dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else {continue}
                let next = ny*width+nx
                if !visited[next] && data[next*4+3] >= 8 {
                    visited[next] = true; pixels.append(next)
                }
            }
        }
    }
    // 此源图的角色区域均超过 1,000 像素，孤立残留最大 13 像素。
    if pixels.count > 16 {
        components += 1
        for index in pixels {retained[index] = true}
    } else {removed += pixels.count}
}
var minX = width, minY = height, maxX = -1, maxY = -1
for index in 0..<(width*height) {
    if retained[index] {
        minX = min(minX,index % width); maxX = max(maxX,index % width)
        minY = min(minY,index / width); maxY = max(maxY,index / width)
    } else {
        for channel in 0..<4 {data[index*4+channel] = 0}
    }
}
guard maxX >= minX, maxY >= minY,
      let cleaned = context.makeImage(),
      let cropped = cleaned.cropping(to:CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)),
      let destination = CGImageDestinationCreateWithURL(output as CFURL,UTType.png.identifier as CFString,1,nil) else {
    fatalError("无法保存清理后的图片")
}
CGImageDestinationAddImage(destination,cropped,nil)
guard CGImageDestinationFinalize(destination) else {fatalError("写入图片失败")}
print("保留 \(components) 个角色区域，移除 \(removed) 个孤立像素及 Alpha < 8 的残留；裁切尺寸 \(cropped.width)×\(cropped.height)。显示层按边界等比居中。")
