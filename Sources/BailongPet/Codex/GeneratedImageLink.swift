import Foundation

enum GeneratedImageLink {
    // 只使用协议公开的已保存文件地址，不读取提示词或内嵌图片数据。
    static func markdown(status:String?,savedPath:String?) -> String? {
        guard status == "completed",let path = savedPath,path.hasPrefix("/") else {return nil}
        let url = URL(fileURLWithPath:path)
        return "[查看生成图片](<\(url.absoluteString)>)"
    }

    static func appending(_ links:[String],to text:String) -> String {
        var result = text
        for link in links where !result.contains(link) {
            if !result.isEmpty {result += "\n\n"}
            result += link
        }
        return result
    }
}
