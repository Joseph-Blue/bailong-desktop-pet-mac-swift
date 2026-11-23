import AppKit

enum SubscriptionManagement {
    case personal, organization, api, bedrock, gcp
    static func forAccount(_ account:[String:Any]?,plan:String) -> Self {
        switch account?["type"] as? String {
        case "apiKey":return .api
        case "amazonBedrock":return .bedrock
        case "gcp":return .gcp
        default:
            return ["Team","Business","Enterprise","Edu","Science"].contains(where:{plan.hasPrefix($0)}) ? .organization : .personal
        }
    }
    var title:String {self == .api || self == .bedrock || self == .gcp ? L10n.text(.usage,"subscriptionManagement.forAccount.text") : L10n.text(.usage,"subscriptionManagement.forAccount.text.2")}
    var destinations:[(String,String)] {
        switch self {
        case .personal:return [(L10n.text(.usage,"subscriptionManagement.forAccount.text.3"),"https://chatgpt.com/settings/billing"),(L10n.text(.usage,"subscriptionManagement.forAccount.text.4"),"https://play.google.com/store/account/subscriptions"),(L10n.text(.usage,"subscriptionManagement.forAccount.text.5"),"https://apps.apple.com/account/subscriptions")]
        case .organization:return [(L10n.text(.usage,"subscriptionManagement.forAccount.text.6"),"https://chatgpt.com/")]
        case .api:return [(L10n.text(.usage,"subscriptionManagement.forAccount.text.7"),"https://platform.openai.com/settings/organization/billing/overview")]
        case .bedrock:return [(L10n.text(.usage,"subscriptionManagement.forAccount.text.8"),"https://console.aws.amazon.com/billing/")]
        case .gcp:return [(L10n.text(.usage,"subscriptionManagement.forAccount.text.9"),"https://console.cloud.google.com/billing")]
        }
    }
}

// 原生圆角按钮与 NSMenu，菜单项打开对应的管理页面。
final class SubscriptionManagementButton:NSButton {
    let management:SubscriptionManagement
    init(management:SubscriptionManagement,font:NSFont) {
        self.management = management
        super.init(frame:.zero)
        title = management.title+"\u{00A0}"; isBordered = true; bezelStyle = .rounded
        self.font = font
        image = NSImage(systemSymbolName:"chevron.down",accessibilityDescription:nil)
        imagePosition = .imageTrailing; imageScaling = .scaleProportionallyDown
        target = self; action = #selector(openMenu); setAccessibilityLabel(management.title)
    }
    required init?(coder:NSCoder) {fatalError()}
    @objc private func openMenu() {
        let menu = AccentMenuRows.menu()
        func add(_ label:String,_ url:String) {
            let item = NSMenuItem(title:label,action:#selector(openDestination(_:)),keyEquivalent:"")
            item.target = self; item.representedObject = url; menu.addItem(item)
        }
        for (label,url) in management.destinations {add(label,url)}
        if management == .personal || management == .organization {
            menu.addItem(.separator())
            add(L10n.text(.usage,"subscriptionManagement.add.text"),"https://chatgpt.com/profile")
        }
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:bounds.maxY),in:self)
    }
    @objc private func openDestination(_ sender:NSMenuItem) {
        guard let address = sender.representedObject as? String,let url = URL(string:address) else {return}
        NSWorkspace.shared.open(url)
    }
}
