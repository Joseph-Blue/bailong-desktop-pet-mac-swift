import Foundation

enum L10n {
    enum Table:String {
        case about = "About", animations = "Animations", app = "App", conversation = "Conversation"
        case diagnostics = "Diagnostics", dialogue = "Dialogue", settings = "Settings"
        case tasks = "Tasks", usage = "Usage", workspace = "Workspace"
    }

    private static let bundle:Bundle = {
        if Bundle.main.bundleURL.pathExtension == "app" {return .main}
        let project = URL(fileURLWithPath:FileManager.default.currentDirectoryPath,isDirectory:true)
        let resources = project.appendingPathComponent("Resources/Localization",isDirectory:true)
        return Bundle(url:resources)!
    }()

    static func text(_ table:Table,_ key:String) -> String {
        bundle.localizedString(forKey:key,value:nil,table:table.rawValue)
    }

    static func format(_ table:Table,_ key:String,_ arguments:String...) -> String {
        String(format:text(table,key),arguments:arguments)
    }

    static func assetText(_ table:Table,_ key:String) -> String? {
        let value = text(table,key)
        return value == key ? nil : value
    }
}
