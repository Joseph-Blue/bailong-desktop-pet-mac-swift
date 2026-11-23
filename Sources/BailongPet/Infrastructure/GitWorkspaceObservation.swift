import Foundation
import CoreServices

// 仅监听当前工作树及 Git 元数据；系统合并文件事件，不扫描目录或轮询。
final class GitWorkspaceObservation {
    private var stream:FSEventStreamRef?
    private var paths = [String]()
    var onChange:() -> Void = {}
    func update(paths:[String]) throws {
        let candidates = Array(Set(paths.map {URL(fileURLWithPath:$0).standardizedFileURL.resolvingSymlinksInPath().path})).sorted()
        let next = candidates.filter {path in !candidates.contains {$0 != path && path.hasPrefix($0+"/")}}
        guard next != self.paths else {return}
        stop()
        guard !next.isEmpty else {return}
        var context = FSEventStreamContext(version:0,info:Unmanaged.passUnretained(self).toOpaque(),retain:nil,release:nil,copyDescription:nil)
        guard let stream = FSEventStreamCreate(nil,{ _,info,_,_,_,_ in
            guard let info else {return}
            Unmanaged<GitWorkspaceObservation>.fromOpaque(info).takeUnretainedValue().onChange()
        },&context,next as CFArray,FSEventStreamEventId(kFSEventStreamEventIdSinceNow),0.4,FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)) else {
            throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspaceObservation.update.error"))
        }
        FSEventStreamSetDispatchQueue(stream,DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
            throw GitWorkspaceFailure(L10n.text(.workspace,"gitWorkspaceObservation.update.error.2"))
        }
        self.stream = stream; self.paths = next
    }
    func stop() {
        if let stream {FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)}
        stream = nil; paths = []
    }
    deinit {stop()}
}
