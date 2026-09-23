#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The incremental cache must never restore build outputs from data it
/// cannot authenticate: a committed `.kswiftk-cache`, a tampered artifact,
/// an unsafe directory, or an unauthenticated manifest all fall back to a
/// full build. Only a private, authenticated cache restores output.
@Suite(.serialized)
struct IncrementalCacheSecurityTests {
    private var tempDir: String

    init() {
        tempDir = NSTemporaryDirectory() + "IncrementalCacheSecurityTest_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    private func makeOptions(input: String, output: String) -> CompilerOptions {
        CompilerOptions(
            moduleName: "Test",
            inputs: [input],
            outputPath: output,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
    }

    private func buildValidCache(at cachePath: String, artifactContents: String = "cached") throws -> CompilerOptions {
        let sourceDir = tempDir + "/src_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir + "/a.kt"
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)
        let options = makeOptions(input: sourceFile, output: tempDir + "/out_\(UUID().uuidString)")

        let cache = IncrementalCompilationCache(cachePath: cachePath)
        cache.computeCurrentFingerprints(for: [sourceFile])
        cache.saveState(dependencyGraph: DependencyGraph(), options: options)

        // Stage a file artifact the way saveState does so restoreCachedOutput
        // has something to verify.
        let buildHash = cache.buildConfigurationHash(for: options)
        let artifactDir = cachePath + "/artifacts/\(buildHash)"
        try FileManager.default.createDirectory(atPath: artifactDir, withIntermediateDirectories: true)
        try artifactContents.write(toFile: artifactDir + "/output", atomically: true, encoding: .utf8)
        let manifest = """
        {
          "version": 1,
          "fingerprints": [],
          "buildConfigurationHash": "\(buildHash)",
          "outputArtifact": {"kind": "file", "relativePath": "artifacts/\(buildHash)/output"}
        }
        """
        try manifest.write(toFile: cachePath + "/manifest.json", atomically: true, encoding: .utf8)
        #expect(IncrementalCacheTrust.writeIntegrityIndex(cachePath: cachePath) != nil)
        return options
    }

    // MARK: - Default location stays out of the workspace

    @Test
    func testDefaultCachePathLivesInPerUserCacheRoot() throws {
        let override = tempDir + "/usercache"
        IncrementalCompilationCache.userCacheRootOverride = override
        defer { IncrementalCompilationCache.userCacheRootOverride = nil }

        let options = makeOptions(input: tempDir + "/in.kt", output: tempDir + "/ws/out")
        let path = try #require(IncrementalCompilationCache.defaultCachePath(for: options))
        #expect(path.hasPrefix(override + "/incremental/"))
        #expect(!path.contains(".kswiftk-cache"))
        #expect(!path.hasPrefix(tempDir + "/ws"))
    }

    @Test
    func testDefaultNamespaceIsolatesInputsAndWorkspace() throws {
        let override = tempDir + "/usercache"
        IncrementalCompilationCache.userCacheRootOverride = override
        defer { IncrementalCompilationCache.userCacheRootOverride = nil }

        let a = makeOptions(input: tempDir + "/a.kt", output: tempDir + "/w1/out")
        let b = makeOptions(input: tempDir + "/b.kt", output: tempDir + "/w1/out")
        let c = makeOptions(input: tempDir + "/a.kt", output: tempDir + "/w2/out")
        #expect(IncrementalCompilationCache.defaultCachePath(for: a)
            != IncrementalCompilationCache.defaultCachePath(for: b))
        #expect(IncrementalCompilationCache.defaultCachePath(for: a)
            != IncrementalCompilationCache.defaultCachePath(for: c))
    }

    @Test
    func testCommittedCacheInWorkspaceIsIgnoredByIncrementalBuild() throws {
        let override = tempDir + "/usercache"
        IncrementalCompilationCache.userCacheRootOverride = override
        defer { IncrementalCompilationCache.userCacheRootOverride = nil }

        let repo = tempDir + "/repo"
        try FileManager.default.createDirectory(
            atPath: repo + "/.git", withIntermediateDirectories: true
        )
        let source = repo + "/main.kt"
        try "fun main() {}".write(toFile: source, atomically: true, encoding: .utf8)
        let output = repo + "/out"

        // A poisoned cache committed next to the output must not be used.
        let poisoned = repo + "/.kswiftk-cache"
        try FileManager.default.createDirectory(
            atPath: poisoned + "/artifacts/x", withIntermediateDirectories: true
        )
        let sentinel = "// poisoned artifact\n"
        try sentinel.write(
            toFile: poisoned + "/artifacts/x/output", atomically: true, encoding: .utf8
        )
        try """
        {"version": 1, "fingerprints": [], "buildConfigurationHash": "x",
         "outputArtifact": {"kind": "file", "relativePath": "artifacts/x/output"}}
        """.write(toFile: poisoned + "/manifest.json", atomically: true, encoding: .utf8)

        let driver = CompilerDriver()
        var options = makeOptions(input: source, output: output)
        options.frontendFlags = ["incremental"]
        let result = driver.runForTesting(options: options)
        #expect(result.exitCode == 0,
                "Incremental build should succeed. Diagnostics: \(result.diagnostics.map(\.message))")

        let produced = try String(contentsOfFile: output + ".kir", encoding: .utf8)
        #expect(produced != sentinel,
                "A cache committed inside the workspace must never be restored")
        #expect(!produced.isEmpty)
    }

    // MARK: - Integrity

    @Test
    func testArtifactByteModificationRejectsRestore() throws {
        let cachePath = tempDir + "/cache"
        let options = try buildValidCache(at: cachePath)

        // Flip one byte inside the cached artifact.
        let artifactsDir = cachePath + "/artifacts"
        let enumerator = try #require(FileManager.default.enumerator(atPath: artifactsDir))
        var artifactFile: String?
        for case let path as String in enumerator where path.hasSuffix("output") {
            artifactFile = artifactsDir + "/" + path
        }
        let artifact = try #require(artifactFile)
        var bytes = try #require(String(contentsOfFile: artifact, encoding: .utf8).data(using: .utf8))
        bytes[0] ^= 0xFF
        try bytes.write(to: URL(fileURLWithPath: artifact))

        let cache2 = IncrementalCompilationCache(cachePath: cachePath)
        cache2.loadPreviousState()
        #expect(!cache2.restoreCachedOutput(for: options))
    }

    @Test
    func testManifestModificationRejectsLoad() throws {
        let cachePath = tempDir + "/cache"
        _ = try buildValidCache(at: cachePath)

        var manifest = try String(contentsOfFile: cachePath + "/manifest.json", encoding: .utf8)
        manifest = manifest.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")
        try manifest.write(toFile: cachePath + "/manifest.json", atomically: true, encoding: .utf8)

        let cache = IncrementalCompilationCache(cachePath: cachePath)
        cache.loadPreviousState()
        #expect(!cache.hasPreviousCache)
    }

    @Test
    func testMissingIntegrityIndexRejectsLoad() throws {
        let cachePath = tempDir + "/cache"
        _ = try buildValidCache(at: cachePath)
        try FileManager.default.removeItem(
            atPath: cachePath + "/" + IncrementalCacheTrust.integrityIndexName
        )

        let cache = IncrementalCompilationCache(cachePath: cachePath)
        cache.loadPreviousState()
        #expect(!cache.hasPreviousCache)
    }

    // MARK: - Location

    @Test
    func testGroupAccessibleCacheDirectoryIsRejected() throws {
        let cachePath = tempDir + "/cache"
        _ = try buildValidCache(at: cachePath)
        #expect(chmod(cachePath, 0o770) == 0)

        let cache = IncrementalCompilationCache(cachePath: cachePath)
        cache.loadPreviousState()
        #expect(!cache.hasPreviousCache)
    }

    @Test
    func testSymlinkedCacheDirectoryIsRejected() throws {
        let realPath = tempDir + "/real-cache"
        _ = try buildValidCache(at: realPath)
        let linkPath = tempDir + "/link-cache"
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: realPath)

        let cache = IncrementalCompilationCache(cachePath: linkPath)
        cache.loadPreviousState()
        #expect(!cache.hasPreviousCache)
    }

    // MARK: - Trusted round trip

    @Test
    func testPrivateAuthenticatedCacheRestoresNormally() throws {
        let cachePath = tempDir + "/cache"
        let options = try buildValidCache(at: cachePath)

        let cache = IncrementalCompilationCache(cachePath: cachePath)
        cache.loadPreviousState()
        #expect(cache.restoreCachedOutput(for: options))
        #expect(try String(contentsOfFile: options.outputPath + ".kir", encoding: .utf8) == "cached")
    }

    @Test
    func testAddedFileInDirectoryArtifactRejectsRestore() throws {
        let cachePath = tempDir + "/cache"
        try FileManager.default.createDirectory(atPath: cachePath, withIntermediateDirectories: true)
        #expect(chmod(cachePath, 0o700) == 0)

        let sourceFile = tempDir + "/dirsrc_\(UUID().uuidString)/a.kt"
        try FileManager.default.createDirectory(
            atPath: URL(fileURLWithPath: sourceFile).deletingLastPathComponent().path,
            withIntermediateDirectories: true
        )
        try "fun main() {}".write(toFile: sourceFile, atomically: true, encoding: .utf8)
        let options = makeOptions(input: sourceFile, output: tempDir + "/dirout_\(UUID().uuidString)")
        let buildHash = IncrementalCompilationCache(cachePath: cachePath)
            .buildConfigurationHash(for: options)

        let artifactDir = cachePath + "/artifacts/\(buildHash)/output"
        try FileManager.default.createDirectory(atPath: artifactDir, withIntermediateDirectories: true)
        try "cached".write(toFile: artifactDir + "/part.o", atomically: true, encoding: .utf8)
        let manifest = """
        {
          "version": 1,
          "fingerprints": [],
          "buildConfigurationHash": "\(buildHash)",
          "outputArtifact": {"kind": "directory", "relativePath": "artifacts/\(buildHash)/output"}
        }
        """
        try manifest.write(toFile: cachePath + "/manifest.json", atomically: true, encoding: .utf8)
        #expect(IncrementalCacheTrust.writeIntegrityIndex(cachePath: cachePath) != nil)

        // Anything added after the index was written must break the restore.
        try "injected".write(toFile: artifactDir + "/injected.o", atomically: true, encoding: .utf8)

        let cache = IncrementalCompilationCache(cachePath: cachePath)
        cache.loadPreviousState()
        #expect(!cache.restoreCachedOutput(for: options))
    }
}
#endif
