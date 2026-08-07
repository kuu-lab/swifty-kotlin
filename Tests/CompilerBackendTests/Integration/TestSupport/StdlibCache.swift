@testable import CompilerCore
@testable import CompilerBackend
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
final class TestStdlibCache: @unchecked Sendable {
    static let shared = TestStdlibCache()

    private let lock = NSRecursiveLock()
    private var didPrepare = false

    func prepare() {
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
        if fm.fileExists(atPath: artifactPath), !isArtifactStale(at: artifactURL, fm: fm) {
            return artifactPath
        }
        // Existing artifact is missing or stale (stdlib source changed).
        try? fm.removeItem(at: artifactURL)

        let buildingBase = artifactPath + ".building"
        let buildingArtifactPath = buildingBase + ".kklib"

        // Remove any stale partial build from a previous run.
        try? fm.removeItem(atPath: buildingBase)
        try? fm.removeItem(atPath: buildingArtifactPath)

        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "KSwiftKStdlib",
            emit: .library,
            outputPath: buildingBase,
            includeStdlib: true,
            stdlibOnly: true
        )

        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)

        guard fm.fileExists(atPath: buildingArtifactPath) else {
            throw TestStdlibCacheError.artifactMissing(buildingArtifactPath)
        }

        try? fm.removeItem(at: artifactURL)
        try fm.moveItem(atPath: buildingArtifactPath, toPath: artifactPath)

        return artifactPath
    }

    private func isArtifactStale(at artifactURL: URL, fm: FileManager) -> Bool {
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
        return hash != BundledKotlinStdlib.manifestHash()
    }
}
