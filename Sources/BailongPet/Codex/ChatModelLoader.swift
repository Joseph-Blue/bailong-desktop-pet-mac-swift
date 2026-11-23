import Foundation

// 每个输入入口各自加载工作区配置；旧目录的异步结果不能覆盖新目录。
final class ChatModelLoader {
    private let connection:CodexConnection
    private var directory:String?, request:UUID?
    init(connection:CodexConnection) {self.connection = connection}
    func invalidate() {directory = nil; request = nil}
    func load(directory:String,settings:ChatModelSettings,force:Bool = false) {
        guard force || self.directory != directory else {return}
        self.directory = directory
        let id = UUID(); request = id; settings.setLoading()
        func finish(_ result:Result<([ChatModel],[String:Any]),Error>) {
            guard self.request == id else {return}
            switch result {
            case .success(let (models,config)):
                let provider = config["model_provider"] as? String ?? "openai"
                let providers = config["model_providers"] as? [String:[String:Any]]
                let definition = providers?[provider]
                let identity = APIProviderDirectory.thirdParty(in:config) ??
                    APIProviderDirectory.identity(id:provider,name:definition?["name"] as? String,baseURL:definition?["base_url"] as? String)
                settings.loaded(models,configuredModel:config["model"] as? String,configuredEffort:config["model_reasoning_effort"] as? String,
                    configuredProvider:provider,configuredServiceTier:config["service_tier"] as? String,
                    providerName:identity.name,providerSummaryName:identity.summaryName,providerIconID:identity.catalogID)
                if provider == "openai" {
                    self.connection.call("account/read",["refreshToken":false]) { response in
                        guard self.request == id else {return}
                        self.request = nil
                        if case .success(let value) = response {
                            let account = value["account"] as? [String:Any]
                            settings.setUsesChatGPTAccount(account?["type"] as? String == "chatgpt")
                        } else {settings.setUsesChatGPTAccount(false)}
                    }
                } else {self.request = nil}
            case .failure(let error):
                self.request = nil; self.directory = nil; settings.failed(error)
            }
        }
        connection.connect { [weak self] error in
            guard let self,self.request == id else {return}
            if let error {finish(.failure(error)); return}
            func page(_ cursor:String?,_ collected:[ChatModel]) {
                var params:[String:Any] = ["limit":100,"includeHidden":false]
                if let cursor {params["cursor"] = cursor}
                self.connection.call("model/list",params) { [weak self] result in
                    guard let self,self.request == id else {return}
                    do {
                        let value = try result.get()
                        let data = try JSONSerialization.data(withJSONObject:value["data"] ?? [])
                        let models = collected + (try JSONDecoder().decode([ChatModel].self,from:data))
                        if let next = value["nextCursor"] as? String {page(next,models); return}
                        self.connection.call("config/read",["includeLayers":false,"cwd":directory]) { response in
                            finish(response.flatMap { value in
                                guard let config = value["config"] as? [String:Any] else {
                                    return .failure(CodexProtocol.Failure.malformed(L10n.text(.conversation,"chatModelLoader.page.text")))
                                }
                                return .success((models,config))
                            })
                        }
                    } catch {finish(.failure(error))}
                }
            }
            page(nil,[])
        }
    }
}
