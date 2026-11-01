import Foundation
import Darwin

// XNU ABI: bsd/sys/proc_info_private.h (PROC_PIDCOALITIONINFO = 20),
// osfmk/mach/coalition.h (resource type = 0; gpu_time is the ninth uint64_t).
// This SPI is intentionally isolated: errors are surfaced, never replaced by
// the ineffective ARM64 TASK_POWER_INFO_V2 GPU counter or system-wide load.
enum GPUStatistics {
    struct Snapshot {
        let coalition: UInt64
        let nanoseconds: UInt64
    }
    struct Failure: Error {
        let message: String
    }
    private typealias Usage = @convention(c) (UInt64, UnsafeMutableRawPointer, Int) -> Int32
    private static let usage: Usage? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "coalition_info_resource_usage") else { return nil }
        return unsafeBitCast(symbol, to: Usage.self)
    }()
    static func read() -> Result<Snapshot, Failure> {
        guard let usage else { return .failure(Failure(message: "系统缺少资源组接口")) }
        // Two coalition IDs and three reserved uint64_t fields, 40 bytes.
        var identifiers = [UInt64](repeating: 0, count: 5)
        let received = identifiers.withUnsafeMutableBytes {
            proc_pidinfo(getpid(), 20, 0, $0.baseAddress, Int32($0.count))
        }
        guard received == 40 else {
            let code = errno
            return .failure(Failure(message: "读取应用组失败：返回 \(received)，errno \(code)"))
        }
        let coalition = identifiers[0]
        guard coalition != 0 else { return .failure(Failure(message: "进程没有资源组")) }
        // Kernel copies min(requested size, struct size); only request the
        // stable prefix through gpu_time, not a guessed current struct layout.
        var prefix = [UInt64](repeating: 0, count: 9)
        let status = prefix.withUnsafeMutableBytes { usage(coalition, $0.baseAddress!, $0.count) }
        guard status == 0 else {
            let code = errno
            return .failure(Failure(message: "读取 GPU 时间失败：errno \(code)（\(String(cString: strerror(code)))）"))
        }
        return .success(Snapshot(coalition: coalition, nanoseconds: prefix[8]))
    }
}
