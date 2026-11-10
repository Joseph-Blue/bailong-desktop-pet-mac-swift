import Foundation

// 独立的配置域让旧版继续使用旧快照，不能写坏新版设置；系统启动注册身份保持不变。
enum SettingsStorage {
    static let schemaVersion = 2
    static let schemaKey = "settingsSchemaVersion"
    private(set) static var compatibilityNotice:String?
    static let domain = "com.bailongpet.appkit.settings.v2"
    static let defaults:UserDefaults = {
        let result = UserDefaults(suiteName:domain)!
        if result.object(forKey:schemaKey) == nil {
            let keys = Array(PetPreferences.defaults.keys)+["x","y","petChatModel","petChatEffort","favorites"]
            var values = [String:Any]()
            for key in keys {
                if let value = UserDefaults.standard.object(forKey:key) {values[key] = value}
            }
            values[schemaKey] = schemaVersion
            result.setPersistentDomain(values,forName:domain)
        }
        if result.integer(forKey:schemaKey) > schemaVersion {
            compatibilityNotice = "这份设置来自更高版本，当前版本无法读取。原设置已保留，暂时使用另一份设置。"
            let recovery = UserDefaults(suiteName:domain+".recovery")!
            return recovery
        }
        return result
    }()
}
