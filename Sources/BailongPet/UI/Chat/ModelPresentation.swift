import AppKit

enum ModelPresentation {
    static func name(_ id:String,displayName:String? = nil) -> String {
        if let displayName,!displayName.isEmpty {return displayName}
        guard id.hasPrefix("gpt-") else {return id}
        // 只规范显示大小写，原模型 ID 继续用于读取及发送。
        return id.split(separator:"-",omittingEmptySubsequences:false).enumerated().map {index,part in
            index == 0 ? "GPT" : part.prefix(1).uppercased()+part.dropFirst()
        }.joined(separator:"-")
    }
    static func summary(model:String,displayName:String? = nil,effort:String) -> String {
        name(model,displayName:displayName)+" · "+effort
    }
}

// 两类会话共用原生模型字段的尺寸、字体和轮廓；交互能力由各子类决定。
class ModelSummaryButton:NSButton {
    override init(frame:NSRect) {
        super.init(frame:frame)
        bezelStyle = .rounded; font = .systemFont(ofSize:13)
        setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        setContentHuggingPriority(.required,for:.horizontal)
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        widthAnchor.constraint(lessThanOrEqualToConstant:320).isActive = true
    }
    required init?(coder:NSCoder) {fatalError()}
}
