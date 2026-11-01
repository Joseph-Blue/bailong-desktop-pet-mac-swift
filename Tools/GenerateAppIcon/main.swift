import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 从已修复的透明 PNG 母版生成 macOS iconset；只做系统重采样，不重绘角色。
func fail(_ message:String) -> NSError {NSError(domain:"BailongAppIcon",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
do {
    guard CommandLine.arguments.count == 3 else {throw fail("用法：GenerateAppIcon <透明 PNG> <输出.iconset>")}
    let input = URL(fileURLWithPath:CommandLine.arguments[1])
    let output = URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
    guard let source = CGImageSourceCreateWithURL(input as CFURL,nil),let image = CGImageSourceCreateImageAtIndex(source,0,nil) else {
        throw fail("无法读取图标源 PNG。")
    }
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    let colorSpace = CGColorSpace(name:CGColorSpace.sRGB)!
    for points in [16,32,128,256,512] {
        for scale in [1,2] {
            let pixels = points*scale
            guard let context = CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:pixels*4,space:colorSpace,
                                          bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw fail("无法创建图标画布。")
            }
            context.interpolationQuality = .high
            let factor = min(CGFloat(pixels)/CGFloat(image.width),CGFloat(pixels)/CGFloat(image.height))
            let size = CGSize(width:CGFloat(image.width)*factor,height:CGFloat(image.height)*factor)
            context.draw(image,in:CGRect(x:(CGFloat(pixels)-size.width)/2,y:(CGFloat(pixels)-size.height)/2,width:size.width,height:size.height))
            let name = "icon_\(points)x\(points)"+(scale == 2 ? "@2x" : "")+".png"
            guard let rendered = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL,UTType.png.identifier as CFString,1,nil) else {
                throw fail("无法创建图标文件："+name)
            }
            CGImageDestinationAddImage(destination,rendered,nil)
            guard CGImageDestinationFinalize(destination) else {throw fail("图标写入失败："+name)}
        }
    }
    print("已生成透明图标集："+output.path)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8))
    exit(1)
}
