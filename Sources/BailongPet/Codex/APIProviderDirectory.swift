import Foundation

struct APIProviderIdentity: Equatable {
    let id:String
    let catalogID:String
    let name:String
    let summaryName:String
    let pageURL:String?

    var heading:String {"当前 API 供应商："+name}
}

enum APIProviderDirectory {
    private struct Entry {
        let id:String
        let aliases:Set<String>
        let hosts:[String]
        let name:String
        let summaryName:String
        let pageURL:String?
    }

    private static let builtInProviders:Set<String> = [
        "openai","amazonbedrock","amazon-bedrock","bedrock","gcp","google","vertex","vertexai"
    ]
    private static let entries:[Entry] = [
        Entry(id:"openai",aliases:["openai"],hosts:["openai.com"],name:"OpenAI",summaryName:"OpenAI",
            pageURL:"https://platform.openai.com/settings/organization/billing/overview"),
        Entry(id:"deepseek",aliases:["deepseek"],hosts:["deepseek.com"],name:"DeepSeek",summaryName:"DeepSeek",
            pageURL:"https://platform.deepseek.com/usage"),
        Entry(id:"xai",aliases:["xai","grok"],hosts:["x.ai"],name:"xAI",summaryName:"xAI",
            pageURL:"https://console.x.ai/team/default/billing"),
        Entry(id:"mistral",aliases:["mistral"],hosts:["mistral.ai"],name:"Mistral AI",summaryName:"Mistral",
            pageURL:"https://admin.mistral.ai/organization/billing"),
        Entry(id:"kimi-cn",aliases:["kimi-cn","moonshot-cn"],hosts:["moonshot.cn"],
            name:"Kimi（中国站）",summaryName:"Kimi CN",pageURL:"https://platform.kimi.com/console/pay"),
        Entry(id:"kimi-global",aliases:["kimi-global","moonshot-global"],hosts:["moonshot.ai"],
            name:"Kimi（国际站）",summaryName:"Kimi Global",pageURL:"https://platform.kimi.ai/console/account"),
        Entry(id:"kimi",aliases:["kimi","moonshot"],hosts:[],name:"Kimi",summaryName:"Kimi",
            pageURL:nil),
        Entry(id:"zhipu-cn",aliases:["zhipu","zhipu-cn","bigmodel","glm"],hosts:["bigmodel.cn","zhipuai.cn"],
            name:"智谱 GLM（中国站）",summaryName:"智谱 GLM",pageURL:"https://bigmodel.cn/finance-center/bill/expensebill/list"),
        Entry(id:"zhipu-global",aliases:["zai","z-ai","zai-global","zhipu-global","glm-global"],hosts:["z.ai"],
            name:"Z.AI GLM（国际站）",summaryName:"Z.AI",pageURL:"https://z.ai/manage-apikey/billing"),
        Entry(id:"bailian-cn",aliases:["bailian-cn","bailian","dashscope","qwen-cn"],
            hosts:["cn-beijing.maas.aliyuncs.com","dashscope.aliyuncs.com"],
            name:"阿里云百炼（北京）",summaryName:"百炼 CN",pageURL:"https://bailian.console.aliyun.com/"),
        Entry(id:"bailian-global",aliases:["bailian-global","bailian-sg","dashscope-intl","qwen-global"],
            hosts:["ap-southeast-1.maas.aliyuncs.com","dashscope-intl.aliyuncs.com"],
            name:"阿里云百炼（新加坡）",summaryName:"百炼 SG",pageURL:"https://modelstudio.console.alibabacloud.com/"),
        Entry(id:"openrouter",aliases:["openrouter","open-router"],hosts:["openrouter.ai"],name:"OpenRouter",summaryName:"OpenRouter",
            pageURL:"https://openrouter.ai/settings/credits"),
        Entry(id:"groq",aliases:["groq"],hosts:["groq.com"],name:"Groq",summaryName:"Groq",
            pageURL:"https://console.groq.com/settings/billing"),
        Entry(id:"bedrock",aliases:["amazon-bedrock","amazonbedrock","bedrock"],hosts:[],
            name:"Amazon Bedrock",summaryName:"Bedrock",pageURL:"https://console.aws.amazon.com/billing/"),
        Entry(id:"gcp",aliases:["gcp","google","vertex","vertexai"],hosts:["googleapis.com","cloud.google.com"],
            name:"Google Cloud Vertex AI",summaryName:"Vertex AI",
            pageURL:"https://console.cloud.google.com/billing")
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
        let displayName = entry?.name ?? configuredName.flatMap {$0.isEmpty ? nil : $0} ?? id
        let pageURL = entry?.pageURL
        let catalogID:String
        switch entry?.id {
        case "kimi-cn","kimi-global":catalogID = "kimi"
        case "zhipu-cn","zhipu-global":catalogID = "zhipu"
        case "bailian-cn","bailian-global":catalogID = "bailian"
        default:catalogID = entry?.id ?? id
        }
        return APIProviderIdentity(id:id,catalogID:catalogID,name:displayName,
            summaryName:entry?.summaryName ?? configuredName.flatMap {$0.isEmpty ? nil : $0} ?? id,
            pageURL:pageURL)
    }

    private static func entry(id:String,name:String?,baseURL:String?) -> Entry? {
        if let baseURL {
            let raw = baseURL.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
            let host = URL(string:raw)?.host?.lowercased() ?? raw.split(separator:"/").first.map(String.init) ?? raw
            if let match = entries.first(where: {entry in
                entry.hosts.contains {host == $0 || host.hasSuffix("."+$0)}
            }) {return match}
        }
        func key(_ value:String) -> String {
            value.lowercased()
                .replacingOccurrences(of:"_",with:"")
                .replacingOccurrences(of:"-",with:"")
        }
        let idKey = key(id)
        let label = name?.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        return entries.first {entry in
            key(entry.id) == idKey || entry.aliases.contains(where:{key($0) == idKey}) ||
                (label.map {entry.name.lowercased() == $0} ?? false)
        }
    }
}
