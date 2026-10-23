@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

/// KUU-3016: a `--profile minimal` stdlib artifact, built once for the suite
/// (a real `--stdlib-only` build), and the diagnostics around it.
@Suite(.serialized)
struct StdlibProfileArtifactTests {
    private static let minimalArtifact: Result<String, Error> = {
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-stdlib-minimal-test-\(UUID().uuidString)")
            .path
        return Result {
            try StdlibArtifactBuilder.build(
                outputBase: outputBase,
                target: TargetTriple.hostDefault(),
                profile: .minimal
            )
        }
    }()

    private func artifact() throws -> String {
        try Self.minimalArtifact.get()
    }

    private func diagnostics(
        compiling source: String,
        profile: StdlibProfile,
        stdlibLibraryPath: String
    ) throws -> [(code: String, message: String)] {
        try diagnostics(compilingAll: [source], profile: profile, stdlibLibraryPath: stdlibLibraryPath)
    }

    private func diagnostics(
        compilingAll sources: [String],
        profile: StdlibProfile,
        stdlibLibraryPath: String
    ) throws -> [(code: String, message: String)] {
        var result: [(code: String, message: String)] = []
        try withTemporaryFiles(contents: sources) { paths in
            let options = CompilerOptions(
                moduleName: "ProfileDiag",
                inputs: paths,
                outputPath: NSTemporaryDirectory() + "profile-diag-\(UUID().uuidString)",
                emit: .kirDump,
                target: TargetTriple.hostDefault(),
                includeStdlib: false,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false,
                stdlibProfile: profile
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try? runSema(ctx)
            result = ctx.diagnostics.diagnostics.map { ($0.code, $0.message) }
        }
        return result
    }

    @Test
    func minimalArtifactManifestRecordsProfileAndProfileHash() throws {
        let path = try artifact()
        let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("manifest.json"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(manifest["stdlibProfile"] as? String == "minimal")
        #expect(manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash(profile: .minimal))
        #expect(manifest["stdlibManifestHash"] as? String != BundledStdlib.manifestHash(profile: .full))
    }

    /// One compile covers the three import cases so the suite pays for a
    /// single (slow, debug-build) Sema run: excluded packages are reported,
    /// kept packages are not, and a user package that merely shares an
    /// excluded prefix is left alone.
    @Test
    func minimalProfileImportDiagnostics() throws {
        let excluded = """
        import kotlin.uuid.Uuid
        import kotlinx.coroutines.runBlocking
        import kotlinx.coroutines.flow.*

        fun usesExcluded() {}
        """
        let kept = """
        import kotlin.math.sqrt
        import kotlin.random.Random
        import kotlinx.io.Buffer

        fun main() {
            println(listOf(3, 1, 2).sorted().map { it * 2 })
            println(sqrt(4.0))
            println(Buffer().size)
        }
        """
        let userPackage = """
        package kotlinx.coroutines.mine

        import kotlinx.coroutines.mine.helper

        fun helper(): Int = 1
        """
        let found = try diagnostics(
            compilingAll: [excluded, kept, userPackage],
            profile: .minimal,
            stdlibLibraryPath: artifact()
        )
        let messages = found.filter { $0.code == "KSWIFTK-LIB-0036" }.map(\.message)
        #expect(messages.count == 3, "\(found)")
        #expect(messages.contains { $0.contains("'kotlin.uuid.Uuid'") })
        // Resolves through a Swift-side synthetic stub, so it must be reported
        // by profile membership rather than by failing to resolve.
        #expect(messages.contains { $0.contains("'kotlinx.coroutines.runBlocking'") })
        #expect(messages.contains { $0.contains("'kotlinx.coroutines.flow.*'") })
        #expect(messages.allSatisfy { $0.contains("--profile minimal") })
        #expect(!messages.contains { $0.contains("kotlinx.coroutines.mine") })
        #expect(!found.contains { $0.code == "KSWIFTK-SEMA-UNRESOLVED-IMPORT" }, "\(found)")
    }

    @Test
    func artifactProfileMustMatchTheRequestedProfile() throws {
        let asFull = try diagnostics(
            compiling: "fun main() { println(1) }",
            profile: .full,
            stdlibLibraryPath: artifact()
        )
        let mismatch = asFull.first { $0.code == "KSWIFTK-LIB-0035" }
        #expect(mismatch != nil, "\(asFull)")
        #expect(mismatch?.message.contains("--profile minimal") == true)
    }

    @Test
    func profilesUseSeparateCacheSlots() throws {
        let fm = FileManager.default
        let cacheDirectory = fm.temporaryDirectory
            .appendingPathComponent("kswiftk-profile-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: cacheDirectory) }
        let target = TargetTriple.hostDefault()
        let source = try artifact()
        var minimalBuilds = 0

        let minimalPath = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory,
            compilerFingerprint: "profile-test",
            profile: .minimal
        ) { base in
            minimalBuilds += 1
            let out = base + ".kklib"
            try fm.copyItem(atPath: source, toPath: out)
            return out
        }
        #expect(URL(fileURLWithPath: minimalPath).lastPathComponent == StdlibProfile.minimal.artifactFileName)
        #expect(minimalBuilds == 1)

        // A second minimal request is served from the cache.
        _ = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory,
            compilerFingerprint: "profile-test",
            profile: .minimal
        ) { _ in
            minimalBuilds += 1
            throw StdlibArtifactBuilder.Error.artifactMissing("unexpected rebuild")
        }
        #expect(minimalBuilds == 1)

        // The full slot is a different directory: the cached minimal artifact
        // must not satisfy it, so the builder runs.
        var fullBuilderRan = false
        #expect(throws: (any Error).self) {
            _ = try StdlibArtifactCache.resolveOrBuildCached(
                target: target,
                cacheDirectory: cacheDirectory,
                compilerFingerprint: "profile-test",
                profile: .full
            ) { _ in
                fullBuilderRan = true
                throw StdlibArtifactBuilder.Error.artifactMissing("stop")
            }
        }
        #expect(fullBuilderRan)
    }
}
