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
/// The artifact is written to a deterministic path under `.build` and guarded by
/// an advisory file lock so that parallel test workers (whether threads in one
/// process or separate `swift test` child processes) coordinate on a single
/// build. The published `.kklib` is immutable after creation, so concurrent tests
/// only read object files and `inline-kir`.
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
        try fm.createDirectory(at: buildURL, withIntermediateDirectories: true, attributes: nil)

        let artifactURL = buildURL.appendingPathComponent("kswiftk-test-stdlib-cache.kklib")
        let artifactPath = artifactURL.path
        let lockPath = artifactPath + ".lock"
        let fingerprintPath = artifactPath + ".compiler-fingerprint"

        // Coordinate across parallel `swift test` workers using an advisory lock.
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

        // Another worker may have built the artifact while we waited.
        if fm.fileExists(atPath: artifactPath),
           !isArtifactStale(at: artifactURL, fingerprintPath: fingerprintPath, fm: fm) {
            return artifactPath
        }
        // Existing artifact is missing or stale (stdlib source or compiler changed).
        try? fm.removeItem(at: artifactURL)
        try? fm.removeItem(atPath: fingerprintPath)

        let buildingBase = artifactPath + ".building"
        let buildingArtifactPath = buildingBase + ".kklib"

        // Remove any stale partial build from a previous run.
        try? fm.removeItem(atPath: buildingBase)
        try? fm.removeItem(atPath: buildingArtifactPath)

        let options = CompilerOptions(
            moduleName: "KSwiftKStdlib",
            inputs: [],
            outputPath: buildingBase,
            emit: .library,
            target: TargetTriple.hostDefault(),
            includeStdlib: true,
            stdlibOnly: true
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )

        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)

        guard fm.fileExists(atPath: buildingArtifactPath) else {
            throw TestStdlibCacheError.artifactMissing(buildingArtifactPath)
        }

        try? fm.removeItem(at: artifactURL)
        try fm.moveItem(atPath: buildingArtifactPath, toPath: artifactPath)

        if let fingerprint = Self.currentCompilerFingerprint() {
            try? fingerprint.write(toFile: fingerprintPath, atomically: true, encoding: .utf8)
        } else {
            try? fm.removeItem(atPath: fingerprintPath)
        }

        return artifactPath
    }

    private func runToKIR(_ ctx: CompilationContext) throws {
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        try SemaPhase().run(ctx)
        try BuildKIRPhase().run(ctx)
    }

    /// A cheap fingerprint (mtime + size) of the `KSwiftKPackageTests` test
    /// binary itself, which statically links every module including
    /// CompilerCore/CompilerBackend (there are no `.dylib`s under `.build` —
    /// `find .build/debug -iname '*.dylib'` returns nothing). The bundled
    /// `.kt` stdlib sources hashed by `BundledStdlib.manifestHash()`
    /// don't change when only Swift-side lowering/codegen/runtime ABI
    /// changes (e.g. a `kk_*` callee gaining a parameter), so that hash
    /// alone can't detect staleness for such changes and a cached artifact
    /// built by the previous binary would otherwise be reused silently
    /// against the new one.
    ///
    /// Deliberately NOT `Bundle.main.executablePath`: under
    /// `swiftpm-testing-helper`, that resolves to the helper binary itself
    /// (part of the Xcode toolchain, unrelated to and untouched by this
    /// repo's own rebuilds), not to `KSwiftKPackageTests` — verified by
    /// comparing the two paths' sizes/mtimes directly, which differed by
    /// orders of magnitude and months. A fixed relative path under `.build`
    /// (mirroring the worker-binary search in
    /// `GoldenHarnessSupport/GoldenHarnessAPI.swift`) is used instead.
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

        guard let binaryPath = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) else {
            return nil
        }
        guard let attrs = try? fm.attributesOfItem(atPath: binaryPath.path),
              let size = attrs[.size] as? UInt64,
              let modified = attrs[.modificationDate] as? Date
        else {
            return nil
        }
        return "\(size)-\(modified.timeIntervalSince1970)"
    }

    private func isArtifactStale(at artifactURL: URL, fingerprintPath: String, fm: FileManager) -> Bool {
        let manifestURL = artifactURL.appendingPathComponent("manifest.json")
        guard fm.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let manifest = object as? [String: Any]
        else {
            return true
        }
        guard let hash = manifest["stdlibManifestHash"] as? String, !hash.isEmpty else {
            return true
        }
        guard hash == BundledStdlib.manifestHash() else { return true }

        // Belt-and-suspenders: the stdlib source hash above only catches
        // `.kt` changes. Also require the compiler binary itself to match
        // the one that built this artifact, so a Swift-side ABI change
        // (no `.kt` diff) invalidates the cache too.
        guard let currentFingerprint = Self.currentCompilerFingerprint() else {
            // Can't determine the running binary's identity; be conservative.
            return true
        }
        guard let savedFingerprint = try? String(contentsOfFile: fingerprintPath, encoding: .utf8) else {
            return true
        }
        return savedFingerprint != currentFingerprint
    }
}
