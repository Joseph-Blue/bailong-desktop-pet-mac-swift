import Foundation

// 每个输入入口各自加载工作区配置；旧目录的异步结果不能覆盖新目录。
final class ChatModelLoader {
    private let connection:CodexConnection
    private var directory:String?, request:UUID?
    init(connection:CodexConnection) {self.connection = connection}
    func invalidate() {directory = nil; request = nil}
    func load(directory:String,settings:ChatModelSettings,force:Bool = false) {
        guard force || self.directory != directory || (request == nil && settings.models.isEmpty) else {return}
        self.directory = directory
        let id = UUID(); request = id; settings.setLoading()
        func finish(_ result:Result<([ChatModel],[String:Any]),Error>) {
            guard self.request == id else {return}
            self.request = nil
            switch result {
            case .success(let (models,config)):
                settings.loaded(models,configuredModel:config["model"] as? String,configuredEffort:config["model_reasoning_effort"] as? String)
            case .failure(let error): self.directory = nil; settings.failed(error)
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
                            finish(response.map {(models,$0["config"] as? [String:Any] ?? [:])})
                        }
                    } catch {finish(.failure(error))}
                }
            }
            page(nil,[])
        }
    }
}
