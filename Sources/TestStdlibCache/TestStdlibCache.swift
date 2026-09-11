import CompilerBackend
import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private enum TestStdlibCacheError: Error, CustomStringConvertible {
    case artifactMissing(String)
    case lockFileCreateFailed(String, Int32)
    case lockFailed(String, Int32)

    var description: String {
        switch self {
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
/// "stale" (see `currentCompilerFingerprint()`), and that fingerprint search
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
        return try Self.resolveOrBuildArtifact(
            buildDirectory: buildURL,
            contentKey: Self.contentKey(),
            fileManager: fm
        ) { outputBase in
            try StdlibArtifactBuilder.build(outputBase: outputBase, target: TargetTriple.hostDefault())
        }
    }

    /// Resolves the shared artifact under `buildDirectory` for `contentKey`,
    /// invoking `builder` to produce it only if no artifact for that key
    /// exists yet. `builder` receives an output-base path (no extension) and
    /// must return the path of the `.kklib` directory it produced there.
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

        // Another worker may have built this content key's artifact while we
        // waited for the lock, or a previous run already left one here.
        // Either way its mere presence at this exact path is proof it is
        // complete (see the type-level doc comment), so trust it as-is —
        // no staleness re-check, no delete.
        if fm.fileExists(atPath: artifactPath) {
            return artifactPath
        }

        let buildingBase = artifactPath + ".building"
        try? fm.removeItem(atPath: buildingBase)
        try? fm.removeItem(atPath: buildingBase + ".kklib")

        let builtPath = try builder(buildingBase)
        guard fm.fileExists(atPath: builtPath) else {
            throw TestStdlibCacheError.artifactMissing(builtPath)
        }
        // Atomic on the same volume: readers can never observe a partially
        // renamed `artifactPath`. And since we still hold the lock and just
        // confirmed `artifactPath` doesn't exist, this can't collide with
        // another builder's output either.
        try fm.moveItem(atPath: builtPath, toPath: artifactPath)
        return artifactPath
    }

    private static func contentKey() -> String {
        let manifestHash = BundledStdlib.manifestHash()
        let fingerprint = currentCompilerFingerprint() ?? "unknown"
        return stableFNV1a64Hex("\(manifestHash)|\(fingerprint)")
    }

    /// Same FNV-1a construction as `BundledStdlib.manifestHash()`, reimplemented
    /// locally since that one is private to its type. Folds an arbitrary,
    /// not-necessarily-filename-safe string (the fingerprint embeds a
    /// floating-point timestamp) into a fixed-length hex token.
    private static func stableFNV1a64Hex(_ string: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }

    /// A cheap fingerprint (mtime + size) of the `KSwiftKPackageTests` test
    /// binary itself, which statically links every module including
    /// CompilerCore/CompilerBackend (there are no `.dylib`s under `.build` —
    /// `find .build/debug -iname '*.dylib'` returns nothing). Folded into
    /// `contentKey()` because the bundled `.kt` stdlib sources hashed by
    /// `BundledStdlib.manifestHash()` don't change when only Swift-side
    /// lowering/codegen/runtime ABI changes (e.g. a `kk_*` callee gaining a
    /// parameter) — that hash alone can't distinguish artifacts built by two
    /// different compiler binaries.
    ///
    /// Deliberately NOT `Bundle.main.executablePath`: under
    /// `swiftpm-testing-helper`, that resolves to the helper binary itself
    /// (part of the Xcode toolchain, unrelated to and untouched by this
    /// repo's own rebuilds), not to `KSwiftKPackageTests` — verified by
    /// comparing the two paths' sizes/mtimes directly, which differed by
    /// orders of magnitude and months.
    ///
    /// Searches the same fixed-depth candidates as before, then falls back to
    /// the same bounded recursive scan of `.build` that
    /// `GoldenHarnessSupport/GoldenHarnessAPI.swift`'s `workerExecutableURL()`
    /// uses to find `GoldenHarnessWorker` — the fixed-depth candidates alone
    /// miss layouts this repo actually produces (e.g. `swiftbuild`'s
    /// `.build/out/Products/Debug/`). Before content-addressing, returning
    /// `nil` here meant "assume stale," which forced every freshly started
    /// process to rebuild and, worse, to delete-then-rebuild the one shared
    /// path every other process's readers were using.
    private static func currentCompilerFingerprint() -> String? {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let workerName = "KSwiftKPackageTests"

        var candidates: [URL] = []
        #if os(Linux)
        candidates.append(contentsOf: [
            cwd.appendingPathComponent(".build/debug/\(workerName).xctest"),
            cwd.appendingPathComponent(".build/x86_64-unknown-linux-gnu/debug/\(workerName).xctest"),
            cwd.appendingPathComponent(".build/aarch64-unknown-linux-gnu/debug/\(workerName).xctest"),
        ])
        #else
        candidates.append(contentsOf: [
            cwd.appendingPathComponent(".build/debug/\(workerName).xctest/Contents/MacOS/\(workerName)"),
            cwd.appendingPathComponent(".build/arm64-apple-macosx/debug/\(workerName).xctest/Contents/MacOS/\(workerName)"),
            cwd.appendingPathComponent(".build/x86_64-apple-macosx/debug/\(workerName).xctest/Contents/MacOS/\(workerName)"),
        ])
        #endif

        for candidate in candidates where fm.isExecutableFile(atPath: candidate.path) {
            return fileFingerprint(at: candidate.path, fm: fm)
        }

        // Last resort: a bounded recursive scan for the `.xctest` bundle
        // itself, mirroring workerExecutableURL()'s fallback search.
        let buildRoot = cwd.appendingPathComponent(".build")
        guard let enumerator = fm.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let targetBundleName = "\(workerName).xctest"
        for case let candidate as URL in enumerator where candidate.lastPathComponent == targetBundleName {
            #if os(Linux)
            let binaryPath = candidate.path
            #else
            let binaryPath = candidate.appendingPathComponent("Contents/MacOS/\(workerName)").path
            #endif
            if fm.isExecutableFile(atPath: binaryPath) {
                return fileFingerprint(at: binaryPath, fm: fm)
            }
        }
        return nil
    }

    private static func fileFingerprint(at path: String, fm: FileManager) -> String? {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64,
              let modified = attrs[.modificationDate] as? Date
        else {
            return nil
        }
        return "\(size)-\(modified.timeIntervalSince1970)"
    }
}
