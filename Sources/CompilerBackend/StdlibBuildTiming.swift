import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Opt-in, cross-process timing for actual stdlib artifact builds.
/// Logging is best-effort and never changes the build result.
public final class StdlibBuildTiming {
    private let path: String
    private let identifier: String
    private let kind: String
    private let startUptime: TimeInterval

    private init(path: String, kind: String) {
        self.path = path
        self.kind = kind
        identifier = UUID().uuidString
        startUptime = ProcessInfo.processInfo.systemUptime
    }

    public static func start(kind: String) -> StdlibBuildTiming? {
        start(kind: kind, path: ProcessInfo.processInfo.environment["KSWIFTK_STDLIB_TIMINGS"])
    }

    static func start(kind: String, path: String?) -> StdlibBuildTiming? {
        guard let path, !path.isEmpty else { return nil }
        let timing = StdlibBuildTiming(path: path, kind: kind)
        timing.append(event: "start", success: nil)
        return timing
    }

    public func finish(success: Bool) {
        append(event: "end", success: success)
    }

    private func append(event: String, success: Bool?) {
        var record: [String: Any] = [
            "version": 1,
            "id": identifier,
            "kind": kind,
            "event": event,
            "pid": Int(getpid()),
            "timestamp": Date().timeIntervalSince1970,
        ]
        if let success {
            record["success"] = success
            record["elapsed_seconds"] = max(0, ProcessInfo.processInfo.systemUptime - startUptime)
        }
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
            return
        }
        data.append(0x0A)
        let fd = path.withCString { open($0, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600) }
        guard fd >= 0 else { return }
        defer { close(fd) }
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { return }
        guard flock(fd, LOCK_EX) == 0 else { return }
        defer { _ = flock(fd, LOCK_UN) }
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, base.advanced(by: offset), bytes.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { break }
                offset += count
            }
        }
    }
}
