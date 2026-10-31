import AppKit
import Foundation

// 为 macOS 26 打包同款符号；仅导出资源，不创建窗口或截图。
let output = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for name in ["capsule.on.rectangle.liquid.glass","capsule.on.rectangle.liquid.glass.fill"] {
    guard let image = NSImage(systemSymbolName:name,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:24,weight:.regular)) else {
        fatalError("当前系统不提供符号：\(name)，请在 macOS 27 上导出。")
    }
    let view = NSImageView(frame:NSRect(x:0,y:0,width:32,height:28))
    view.image = image; view.contentTintColor = .black; view.imageScaling = .scaleProportionallyUpOrDown
    let data = view.dataWithPDF(inside:view.bounds)
    try data.write(to:output.appendingPathComponent(name+".pdf"))
}
