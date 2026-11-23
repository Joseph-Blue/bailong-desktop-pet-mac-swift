import Foundation

struct HuggingFaceSpace:Hashable {
    let owner:String, name:String

    init?(host:String?,repository:String?) {
        guard let host = host?.lowercased(),host == "huggingface.co" || host == "hf.co",let repository else {return nil}
        let path = repository.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        let components = path.split(separator:"/",omittingEmptySubsequences:false)
        guard components.count == 3,components[0] == "spaces" else {return nil}
        let owner = String(components[1])
        let name = components[2].hasSuffix(".git") ? String(components[2].dropLast(4)) : String(components[2])
        let valid = CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard [owner,name].allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(valid.contains)}) else {return nil}
        self.owner = owner; self.name = name
    }

    struct Runtime:Decodable,Equatable {
        enum Badge:String {
            case running = "RUN", building = "BLD", starting = "STR", paused = "PAU", stopped = "STP", error = "ERR"
        }
        let stage:String

        var badge:Badge? {
            switch stage {
            case "RUNNING":return .running
            case "BUILDING","RUNNING_BUILDING":return .building
            case "APP_STARTING","RUNNING_APP_STARTING":return .starting
            case "PAUSED":return .paused
            case "STOPPED":return .stopped
            case "BUILD_ERROR","RUNTIME_ERROR","CONFIG_ERROR","NO_APP_FILE":return .error
            default:return nil
            }
        }
        var title:String {
            let key = "spaceStatus.stage."+stage
            return L10n.format(.workspace,"spaceStatus.detail",
                L10n.assetText(.workspace,key) ?? L10n.text(.workspace,"spaceStatus.unknown"),stage)
        }
    }

    enum Result:Equatable {case runtime(Runtime), unavailable}

    private static let session:URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration:configuration)
    }()

    func requestStatus(completion:@escaping (Result) -> Void) -> URLSessionDataTask {
        let url = URL(string:"https://huggingface.co/api/spaces/"+owner+"/"+name+"/runtime")!
        return Self.session.dataTask(with:url) {data,response,error in
            let result:Result
            if error == nil,(response as? HTTPURLResponse)?.statusCode == 200,
               let data,let runtime = try? JSONDecoder().decode(Runtime.self,from:data),!runtime.stage.isEmpty {
                result = .runtime(runtime)
            } else {
                result = .unavailable
            }
            DispatchQueue.main.async {completion(result)}
        }
    }
}
