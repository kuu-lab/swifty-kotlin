import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum MacOSPrelinkedObjects {
    private static let cacheVersion = "macos-prelink-v1"
    private static let lock = NSLock()

    static func resolve(
        inputs: [String],
        forceLoadPaths: [String] = [],
        cacheDirectory: URL,
        driver: String,
        target: String,
        phaseTimer: PhaseTimer? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        build: (([String], [String], URL) throws -> Void)? = nil
    ) -> String? {
        guard inputs.count > 2,
              environment["KSWIFTK_NO_LINK_PRELINK"] != "1"
        else { return nil }

        lock.lock()
        defer { lock.unlock() }

        var keyParts = [cacheVersion, driver, fileSignature(driver) ?? "missing", target]
        for input in inputs {
            guard let signature = fileSignature(input) else { return nil }
            keyParts.append(input)
            keyParts.append(signature)
        }
        for path in forceLoadPaths {
            guard let signature = fileSignature(path) else { return nil }
            keyParts.append("force_load")
            keyParts.append(path)
            keyParts.append(signature)
        }
        let key = CodegenRuntimeSupport.stableFNV1a64Hex(keyParts.joined(separator: "\u{0}"))
        let cached = cacheDirectory.appendingPathComponent("prelinked-\(key).o")

        if TrustedFileSystem.isTrustedDirectory(cacheDirectory.path),
           MacOSLinkerPlan.trustedCacheFile(cached) {
            return cached.path
        }

        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard TrustedFileSystem.isTrustedDirectory(cacheDirectory.path) else { return nil }

        let temporary = cacheDirectory
            .appendingPathComponent("prelinked-\(key)-\(UUID().uuidString).tmp.o")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            if let build {
                try build(inputs, forceLoadPaths, temporary)
            } else {
                _ = try CommandRunner.run(
                    executable: driver,
                    arguments: ["-r", "-nostdlib", "-target", target] + inputs
                        + forceLoadPaths.map { "-Wl,-force_load,\($0)" }
                        + ["-o", temporary.path],
                    phaseTimer: phaseTimer, subPhaseName: "Link/clang-prelink"
                )
            }
        } catch {
            return nil
        }
        guard FileManager.default.fileExists(atPath: temporary.path) else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if (try? FileManager.default.moveItem(at: temporary, to: cached)) != nil {
            return cached.path
        }
        if MacOSLinkerPlan.trustedCacheFile(cached) {
            return cached.path
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: cached.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            try? FileManager.default.removeItem(at: cached)
        }
        return (try? FileManager.default.moveItem(at: temporary, to: cached)) != nil
            ? cached.path
            : nil
    }

    private static func fileSignature(_ path: String) -> String? {
        var status = stat()
        guard path.withCString({ stat($0, &status) }) == 0 else { return nil }
        #if os(Linux)
        let seconds = status.st_mtim.tv_sec
        let nanoseconds = status.st_mtim.tv_nsec
        #else
        let seconds = status.st_mtimespec.tv_sec
        let nanoseconds = status.st_mtimespec.tv_nsec
        #endif
        return [status.st_dev, status.st_ino, status.st_size, seconds, nanoseconds]
            .map { String(describing: $0) }
            .joined(separator: ":")
    }
}
