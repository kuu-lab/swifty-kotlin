#if canImport(Testing)
import Foundation
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct StdlibProfileTests {
    @Test
    func excludedPrefixesMatchWholePackageSegmentsOnly() {
        #expect(StdlibProfile.isExcludedFromMinimal(package: "kotlinx.coroutines"))
        #expect(StdlibProfile.isExcludedFromMinimal(package: "kotlinx.coroutines.flow"))
        #expect(StdlibProfile.isExcludedFromMinimal(package: "kotlin.io.path"))
        #expect(StdlibProfile.isExcludedFromMinimal(package: "kotlin.test.assertions"))
        // A sibling that merely shares a string prefix is not excluded.
        #expect(!StdlibProfile.isExcludedFromMinimal(package: "kotlin.testing"))
        #expect(!StdlibProfile.isExcludedFromMinimal(package: "kotlin.io"))
        // Kept because bundled `kotlin.io` / collection sources depend on it.
        #expect(!StdlibProfile.isExcludedFromMinimal(package: "kotlinx.io"))
        #expect(!StdlibProfile.isExcludedFromMinimal(package: "kotlin.concurrent"))
        #expect(!StdlibProfile.isExcludedFromMinimal(package: "kotlinx"))
        #expect(!StdlibProfile.isExcludedFromMinimal(package: "kotlin.collections"))
        #expect(!StdlibProfile.isExcludedFromMinimal(package: ""))
    }

    @Test
    func declaredPackageReadsFirstPackageLine() {
        let source = "// header\n/* block */\npackage kotlin.text\n\nfun f() {}\n"
        #expect(StdlibProfile.declaredPackage(in: Data(source.utf8)) == "kotlin.text")
        #expect(StdlibProfile.declaredPackage(in: Data("fun f() {}".utf8)).isEmpty)
    }

    @Test
    func minimalSourcesAreStrictSubsetOfFull() throws {
        let full = try BundledStdlib.collectBundledStdlibSources(profile: .full)
        let minimal = try BundledStdlib.collectBundledStdlibSources(profile: .minimal)
        #expect(!minimal.isEmpty)
        #expect(minimal.count < full.count)
        let fullPaths = Set(full.map(\.path))
        #expect(minimal.allSatisfy { fullPaths.contains($0.path) })
        #expect(minimal.contains { $0.path == "__bundled_kotlin/Pair/Pair.kt" })
        for source in minimal {
            let package = StdlibProfile.declaredPackage(in: source.contents)
            #expect(!StdlibProfile.isExcludedFromMinimal(package: package), "\(source.path) -> \(package)")
        }
        // Order stays deterministic (fileID order is a golden-stability invariant).
        #expect(minimal.map(\.path) == minimal.map(\.path).sorted())
    }

    @Test
    func profilesHaveDistinctManifestHashes() {
        #expect(BundledStdlib.manifestHash(profile: .full) != BundledStdlib.manifestHash(profile: .minimal))
        #expect(BundledStdlib.manifestHash() == BundledStdlib.manifestHash(profile: .full))
    }

    @Test
    func excludedPackagesListsWhatMinimalDrops() {
        #expect(BundledStdlib.excludedPackages(for: .full).isEmpty)
        let excluded = BundledStdlib.excludedPackages(for: .minimal)
        #expect(excluded.contains("kotlinx.coroutines"))
        #expect(!excluded.contains("kotlin.collections"))
    }

    @Test
    func injectionHonorsProfile() throws {
        let options = CompilerOptions(
            moduleName: "ProfileInjection",
            inputs: [],
            outputPath: NSTemporaryDirectory() + "profile-injection",
            emit: .library,
            target: CompilerTestSupport.defaultTargetTriple(),
            stdlibOnly: true,
            allowDefaultStdlibLibrary: false,
            stdlibProfile: .minimal
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try LoadSourcesPhase().run(ctx)
        let paths = ctx.sourceManager.fileIDs().map { ctx.sourceManager.path(of: $0) }
        #expect(paths.contains("__bundled_kotlin/Pair/Pair.kt"))
        #expect(!paths.contains { $0.hasPrefix("__bundled_kotlinx/coroutines/") })
        #expect(paths.contains { $0.hasPrefix("__bundled_kotlinx/io/") })
    }
}
#endif
