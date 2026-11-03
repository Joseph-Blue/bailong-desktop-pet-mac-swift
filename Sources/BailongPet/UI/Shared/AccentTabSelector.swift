import AppKit

// 关于页与对话模式共用原生标签条；仅选中段使用应用色，文字与轮廓交给 AppKit。
final class AccentTabSelector:NSSegmentedControl {
    var onSelect:(Int) -> Void = {_ in}
    init(labels:[String]) {
        super.init(frame:.zero)
        segmentCount = labels.count; trackingMode = .selectOne; segmentStyle = .rounded
        for (index,title) in labels.enumerated() {setLabel(title,forSegment:index)}
        selectedSegment = 0; font = .systemFont(ofSize:13)
        target = self; action = #selector(changed)
        NotificationCenter.default.addObserver(self,selector:#selector(refreshAccent),name:AppAccent.didChange,object:nil)
        refreshAccent()
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func changed() {onSelect(selectedSegment)}
    @objc private func refreshAccent() {
        selectedSegmentBezelColor = AppAccent.color
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance(); refreshAccent()}
}
