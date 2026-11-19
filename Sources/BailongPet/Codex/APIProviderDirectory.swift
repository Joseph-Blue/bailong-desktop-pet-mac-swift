import Foundation

struct APIProviderIdentity: Equatable {
    let id:String
    let catalogID:String
    let name:String
    let pageURL:String?

    var heading:String {"当前 API 供应商："+name}
    var pageTitle:String {"打开 "+name+" 余额查询"}
}

enum APIProviderDirectory {
    private struct Entry {
        let id:String
        let aliases:Set<String>
        let hosts:[String]
        let name:String
        let pageURL:String?
    }

    private static let builtInProviders:Set<String> = [
        "openai","amazonBedrock","amazon-bedrock","bedrock","gcp","google","vertex"
    ]
    private static let entries:[Entry] = [
        Entry(id:"openai",aliases:["openai"],hosts:["openai.com"],name:"OpenAI",
            pageURL:"https://platform.openai.com/settings/organization/billing/overview"),
        Entry(id:"deepseek",aliases:["deepseek"],hosts:["deepseek.com"],name:"DeepSeek",
            pageURL:"https://platform.deepseek.com/usage"),
        Entry(id:"xai",aliases:["xai","grok"],hosts:["x.ai"],name:"xAI",
            pageURL:"https://console.x.ai/team/default/billing"),
        Entry(id:"mistral",aliases:["mistral"],hosts:["mistral.ai"],name:"Mistral",
            pageURL:"https://admin.mistral.ai/organization/billing"),
        Entry(id:"kimi",aliases:["kimi","moonshot"],hosts:["kimi.com","kimi.ai","moonshot.cn","moonshot.ai"],name:"Kimi",
            pageURL:"https://platform.kimi.com/console/pay"),
        Entry(id:"zhipu",aliases:["zhipu","bigmodel","glm"],hosts:["bigmodel.cn","zhipuai.cn"],name:"智谱 GLM",
            pageURL:"https://bigmodel.cn/finance-center/bill/expensebill/list"),
        Entry(id:"openrouter",aliases:["openrouter","open-router"],hosts:["openrouter.ai"],name:"OpenRouter",
            pageURL:"https://openrouter.ai/settings/credits"),
        Entry(id:"groq",aliases:["groq"],hosts:["groq.com"],name:"Groq",
            pageURL:"https://console.groq.com/settings/billing")
    ]

    // 供应商只取 Codex 当前配置；不从模型名称、登录身份或凭证推断。
    static func thirdParty(in config:[String:Any]) -> APIProviderIdentity? {
        guard let rawID = config["model_provider"] as? String else {return nil}
        let id = rawID.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !id.isEmpty,!builtInProviders.contains(id.lowercased()) else {return nil}
        let providers = config["model_providers"] as? [String:[String:Any]]
        let definition = providers?[id]
        return identity(id:id,name:definition?["name"] as? String,baseURL:definition?["base_url"] as? String)
    }

    static func identity(id:String,name:String? = nil,baseURL:String? = nil) -> APIProviderIdentity {
        let configuredName = name?.trimmingCharacters(in:.whitespacesAndNewlines)
        let entry = entry(id:id,name:configuredName,baseURL:baseURL)
        return APIProviderIdentity(id:id,catalogID:entry?.id ?? id,
            name:configuredName.flatMap {$0.isEmpty ? nil : $0} ?? entry?.name ?? id,
            pageURL:entry?.pageURL)
    }

    private static func entry(id:String,name:String?,baseURL:String?) -> Entry? {
        let normalized = id.lowercased().replacingOccurrences(of:"_",with:"-")
        if let match = entries.first(where: {$0.id == normalized || $0.aliases.contains(normalized)}) {return match}
        let candidates = [baseURL,name,id].compactMap {$0}.map {$0.lowercased()}
        return entries.first {entry in
            candidates.contains {value in
                entry.id == value || entry.aliases.contains(value) ||
                    entry.hosts.contains(where: {host in value == host || value.contains("."+host) || value.contains("//"+host)})
            }
        }
    }
}
