import CompilerBackend
import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private enum TestStdlibCacheError: Error, CustomStringConvertible {
    case compilerFingerprintUnavailable
    case artifactMissing(String)
    case lockFileCreateFailed(String, Int32)
    case lockFailed(String, Int32)

    var description: String {
        switch self {
        case .compilerFingerprintUnavailable:
            return "Could not identify the loaded compiler binary; refusing to reuse a shared stdlib artifact"
        case .artifactMissing(let path):
            return "Shared stdlib artifact was not produced at \(path)"
        case .lockFileCreateFailed(let path, let errnoCode):
            return "Could not create lock file '\(path)': errno \(errnoCode)"
        case .lockFailed(let path, let errnoCode):
            return "Could not acquire lock file '\(path)': errno \(errnoCode)"
        }
    }
}

/// Builds a single shared bundled-stdlib `.kklib` and publishes it through
/// ``CompilerOptions/defaultStdlibLibraryPath`` so that every test that asks for
/// bundled stdlib can reuse the precompiled artifact instead of recompiling the
/// frontend-to-KIR pipeline.
///
/// The artifact path is content-addressed by what it's built from — see
/// `contentKey()` — rather than fixed. An artifact at a given content key's
/// path is only ever written by the atomic rename at the end of
/// `resolveOrBuildArtifact`, so if it exists it is always a complete, correct
/// build for that key; nothing in this type ever deletes an existing
/// artifact. A different key (different stdlib source or compiler binary)
/// simply resolves to a different path alongside it.
///
/// This matters because readers of the published path — a `GoldenHarnessWorker`
/// subprocess, or another `swift test` process launch sharing the same
/// `.build` directory — never hold this class's lock while they read; they
/// were simply handed a path by an earlier, already-returned `prepare()`
/// call. An earlier version of this cache used one fixed path plus an
/// mtime/size "staleness" check, and deleted-then-rebuilt in place when that
/// check said stale. Because the check treats an unresolvable fingerprint as
/// "stale", and that fingerprint search
/// could fail to locate the test binary under some build layouts, a fresh
/// process could decide a perfectly valid, in-use artifact was stale and
/// delete it out from under a worker that was still reading it. Content
/// addressing removes the delete entirely: "stale" is just "no artifact
/// exists yet at this key's path," which never requires touching another
/// key's path.
public final class TestStdlibCache: @unchecked Sendable {
    public static let shared = TestStdlibCache()

    private let lock = NSRecursiveLock()
    private var didPrepare = false

    public func prepare() {
        lock.lock()
        defer { lock.unlock() }

        guard !didPrepare else { return }
        didPrepare = true

        do {
            let path = try build()
            CompilerOptions.defaultStdlibLibraryPath = path
        } catch {
            let message = "[TestStdlibCache] Failed to build shared stdlib artifact: \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }

    private func build() throws -> String {
        let fm = FileManager.default
        let buildURL = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent(".build", isDirectory: true)
        let worker = TestStdlibWorkerProvenance.resolve()
        let imageFingerprint: String?
        if worker == nil {
            imageFingerprint = TestStdlibWorkerProvenance.fullImageFingerprint(
                imageURL: Self.currentCompilerImageURL(), context: TestStdlibCompilerIdentity.current()
            )
        } else {
            imageFingerprint = nil
        }
        let manifestHash = BundledStdlib.manifestHash()
        let key: String
        if let worker {
            key = FileFingerprint.compute(
                for: "test-stdlib-worker-key",
                contents: Data("\(manifestHash)|\(worker.fingerprint)".utf8)
            ).contentHash
        } else {
            key = try Self.contentKey(manifestHash: manifestHash, compilerFingerprint: imageFingerprint)
        }
        return try Self.resolveOrBuildArtifact(
            buildDirectory: buildURL,
            contentKey: key,
            fileManager: fm
        ) { outputBase in
            if let worker {
                return try TestStdlibWorkerProvenance.build(worker: worker, outputBase: outputBase)
            }
            return try StdlibArtifactBuilder.build(outputBase: outputBase, target: TargetTriple.hostDefault())
        }
    }

    /// `builder` receives an output-base path (no extension) and must return
    /// the path of the `.kklib` directory it produced there.
    ///
    /// Exposed as an injectable-builder helper (rather than folded directly
    /// into `build()`) so tests can exercise the locking/no-delete contract
    /// with a fast fake builder instead of the real, multi-second stdlib
    /// compile.
    static func resolveOrBuildArtifact(
        buildDirectory: URL,
        contentKey: String,
        fileManager fm: FileManager = .default,
        builder: (_ outputBase: String) throws -> String
    ) throws -> String {
        try fm.createDirectory(at: buildDirectory, withIntermediateDirectories: true)

        let artifactURL = buildDirectory.appendingPathComponent("kswiftk-test-stdlib-cache-\(contentKey).kklib")
        let artifactPath = artifactURL.path
        let lockPath = artifactPath + ".lock"

        // Coordinate across parallel `swift test` workers using an advisory
        // lock, keyed to this exact content-addressed path so builders for
        // different keys never block on each other.
        let lockFd = lockPath.withCString { path in
            open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard lockFd >= 0 else {
            throw TestStdlibCacheError.lockFileCreateFailed(lockPath, errno)
        }
        defer {
            _ = flock(lockFd, LOCK_UN)
            close(lockFd)
        }
        guard flock(lockFd, LOCK_EX) == 0 else {
            throw TestStdlibCacheError.lockFailed(lockPath, errno)
        }

        cleanupStaleStaging(
            buildDirectory: buildDirectory,
            olderThan: Date().addingTimeInterval(-3600),
            fileManager: fm
        )

        // Another worker may have built this content key's artifact while we
        // waited for the lock, or a previous run already left one here.
        // Either way its mere presence at this exact path is proof it is
        // complete (see the type-level doc comment), so trust it as-is —
        // no staleness re-check, no delete.
        if fm.fileExists(atPath: artifactPath) {
            return artifactPath
        }

        // A child worker can briefly survive a killed parent after its lock is
        // released. Never let the next attempt delete or reuse that path.
        let buildingBase = artifactPath + ".building-\(getpid())-\(UUID().uuidString)"
        let stageLockPath = buildingBase + ".lock"
        let stageFd = stageLockPath.withCString { path in
            open(path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard stageFd >= 0 else { throw TestStdlibCacheError.lockFileCreateFailed(stageLockPath, errno) }
        defer {
            _ = flock(stageFd, LOCK_UN)
            close(stageFd)
        }
        guard flock(stageFd, LOCK_SH) == 0 else { throw TestStdlibCacheError.lockFailed(stageLockPath, errno) }

        let builtPath = try builder(buildingBase)
        guard fm.fileExists(atPath: builtPath) else {
            throw TestStdlibCacheError.artifactMissing(builtPath)
        }
        // Atomic on the same volume: readers can never observe a partially
        // renamed `artifactPath`. And since we still hold the lock and just
        // confirmed `artifactPath` doesn't exist, this can't collide with
        // another builder's output either.
        try fm.moveItem(atPath: builtPath, toPath: artifactPath)
        try? fm.removeItem(atPath: stageLockPath)
        return artifactPath
    }

    /// Reclaim only old staging trees whose parent and worker have both
    /// released their shared attempt lock. Keep the lock file itself so an
    /// already-open descriptor cannot be split from a newly created lock.
    static func cleanupStaleStaging(
        buildDirectory: URL,
        olderThan cutoff: Date,
        fileManager fm: FileManager = .default
    ) {
        guard let entries = try? fm.contentsOfDirectory(atPath: buildDirectory.path) else { return }
        for entry in entries where entry.hasPrefix("kswiftk-test-stdlib-cache-")
            && entry.contains(".kklib.building-") && entry.hasSuffix(".lock") {
            let lockPath = buildDirectory.appendingPathComponent(entry).path
            guard let attrs = try? fm.attributesOfItem(atPath: lockPath),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  let modified = attrs[.modificationDate] as? Date, modified < cutoff else { continue }
            let fd = lockPath.withCString { open($0, O_RDWR | O_NOFOLLOW) }
            guard fd >= 0 else { continue }
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                let base = String(lockPath.dropLast(".lock".count))
                try? fm.removeItem(atPath: base + ".kklib")
                _ = flock(fd, LOCK_UN)
            }
            close(fd)
        }
    }

    /// Missing compiler identity must not map to a reusable "unknown" key.
    /// `prepare()` reports this error and leaves source-based compilation available.
    static func contentKey(manifestHash: String, compilerFingerprint: String?) throws -> String {
        guard let compilerFingerprint, !compilerFingerprint.isEmpty else {
            throw TestStdlibCacheError.compilerFingerprintUnavailable
        }
        return StableFNV1a64.hex("\(manifestHash)|\(compilerFingerprint)")
    }

    /// Locate the image containing this module, which SwiftPM statically links
    /// alongside CompilerCore and CompilerBackend in both aggregate and per-target
    /// test products. Under swiftpm-testing-helper, Bundle.main identifies the
    /// toolchain helper instead; searching .build can select an unrelated, stale
    /// product when multiple layouts or configurations coexist.
    static func currentCompilerImageURL() -> URL? {
        #if canImport(Darwin)
        let anchor: @convention(c) () -> Void = testStdlibCacheImageAnchor
        var info = Dl_info()
        guard dladdr(unsafeBitCast(anchor, to: UnsafeRawPointer.self), &info) != 0,
              let filename = info.dli_fname
        else {
            return nil
        }
        return URL(fileURLWithPath: String(cString: filename)).standardizedFileURL
        #elseif os(Linux)
        // Linux SwiftPM runs the statically linked .xctest executable directly.
        return URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
        #else
        return nil
        #endif
    }

    /// Fingerprint the actual loaded image by content, keeping its path to
    /// separate products/configurations. Relinking or touching identical bytes
    /// does not invalidate the artifact, while same-size, same-mtime changes do.
    /// Fail closed if the image cannot be read or changes while it is hashed.
    static func currentCompilerFingerprint(
        compilerImageURL: URL? = currentCompilerImageURL(),
        fileManager fm: FileManager = .default
    ) -> String? {
        guard let compilerImageURL,
              let before = try? fm.attributesOfItem(atPath: compilerImageURL.path),
              before[.type] as? FileAttributeType == .typeRegular,
              let size = before[.size] as? UInt64,
              let modified = before[.modificationDate] as? Date,
              let bytes = try? Data(contentsOf: compilerImageURL, options: [.mappedIfSafe]),
              UInt64(bytes.count) == size
        else {
            return nil
        }
        let hash = FileFingerprint.compute(for: compilerImageURL.path, contents: bytes).contentHash
        guard let after = try? fm.attributesOfItem(atPath: compilerImageURL.path),
              after[.type] as? FileAttributeType == .typeRegular,
              after[.size] as? UInt64 == size,
              after[.modificationDate] as? Date == modified,
              before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber
        else {
            return nil
        }
        return "loaded-image-v2|\(compilerImageURL.path)|\(hash)"
    }
}

#if canImport(Darwin)
// A C function pointer lets dladdr resolve this module's loaded Mach-O image,
// including when swiftpm-testing-helper dynamically loads an .xctest bundle.
@_cdecl("kswiftk_test_stdlib_cache_image_anchor")
private func testStdlibCacheImageAnchor() {}
#endif
