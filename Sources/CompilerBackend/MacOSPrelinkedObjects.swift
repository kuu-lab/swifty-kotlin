import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Collapses a link's compiler-owned object inputs — packaged runtime objects
/// and `.kklib` objects, identical on every compile — into a single
/// relocatable object via `clang -r`. The merged object is cached under the
/// linker cache directory keyed by every input's content signature, so a warm
/// link hands the driver three inputs (user object, entry wrapper, merged
/// object) instead of hundreds (KUU-2677).
///
/// Any failure — an unreadable input, an untrusted or unwritable cache
/// directory, a failed partial link — resolves to `nil` and the caller falls
/// back to passing the original inputs to the driver.
enum MacOSPrelinkedObjects {
    private static let cacheVersion = "macos-prelink-v1"
    private static let lock = NSLock()

    static func resolve(
        inputs: [String],
        cacheDirectory: URL,
        driver: String,
        target: String,
        phaseTimer: PhaseTimer? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        build: (([String], URL) throws -> Void)? = nil
    ) -> String? {
        // Below three objects a partial link cannot shrink the input count.
        guard inputs.count > 2,
              environment["KSWIFTK_NO_LINK_PRELINK"] != "1"
        else { return nil }

        // Same-process dedup only; cross-process correctness comes from the
        // atomic publish below, never from this lock.
        lock.lock()
        defer { lock.unlock() }

        var keyParts = [cacheVersion, driver, fileSignature(driver) ?? "missing", target]
        for input in inputs {
            guard let signature = fileSignature(input) else { return nil }
            keyParts.append(input)
            keyParts.append(signature)
        }
        let key = CodegenRuntimeSupport.stableFNV1a64Hex(keyParts.joined(separator: "\u{0}"))
        let cached = cacheDirectory.appendingPathComponent("prelinked-\(key).o")

        if TrustedFileSystem.isTrustedDirectory(cacheDirectory.path),
           MacOSLinkerPlan.trustedCacheFile(cached) {
            return cached.path
        }

        // Cache writes must not prevent linking (read-only package roots), so
        // every filesystem step below fails open into the per-input fallback.
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
                try build(inputs, temporary)
            } else {
                _ = try CommandRunner.run(
                    executable: driver,
                    arguments: ["-r", "-nostdlib", "-target", target] + inputs + ["-o", temporary.path],
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
        // A concurrent compile may have published the same key first — its
        // content is identical by construction, so reusing it is safe.
        if MacOSLinkerPlan.trustedCacheFile(cached) {
            return cached.path
        }
        // Replace only a plain stale file; anything else (a directory planted
        // at the name) fails open into the per-input fallback.
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: cached.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            try? FileManager.default.removeItem(at: cached)
        }
        return (try? FileManager.default.moveItem(at: temporary, to: cached)) != nil
            ? cached.path
            : nil
    }

    /// Content identity for cache keys: inode + size + nanosecond mtime. A
    /// single `stat` per input keeps the cache-hit path near-free; reusing
    /// `MacOSLinkerPlan.signature` (URL resolution + Foundation attributes)
    /// would cost ~20ms over hundreds of objects per compile.
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
