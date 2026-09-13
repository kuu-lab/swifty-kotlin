#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BundledStdlibOrderingTests {
    @Test
    func testBundledSourcesAreLoadedBeforeUserInputsInDictionaryOrder() throws {
        try withTemporaryFiles(contents: [
            "fun alpha(): Int = 1",
            "fun beta(): Int = 2",
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths)

            try LoadSourcesPhase().run(ctx)

            let orderedPaths = ctx.sourceManager.fileIDs().map { ctx.sourceManager.path(of: $0) }
            let bundledEntries = orderedPaths.enumerated()
                .filter { $0.element.hasPrefix("__bundled_") }
            let userEntries = orderedPaths.enumerated()
                .filter { paths.contains($0.element) }

            #expect(!bundledEntries.isEmpty, "Bundled stdlib sources should be injected.")
            #expect(userEntries.count == paths.count)

            let lastBundledOffset = try #require(bundledEntries.map { $0.offset }.max())
            let firstUserOffset = try #require(userEntries.map { $0.offset }.min())
            #expect(lastBundledOffset < firstUserOffset)

            let bundledPaths = bundledEntries.map { $0.element }
            #expect(bundledPaths == bundledPaths.sorted())
            #expect(bundledPaths.contains { $0.hasSuffix("kotlin/text/StringIndentFormat.kt") })
            #expect(bundledPaths.contains { $0.hasSuffix("kotlin/text/StringSearchReplace.kt") })
        }
    }

    @Test
    func testLexAndParseRecordBundledStdlibSubPhases() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path], frontendFlags: ["time-phases"])
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)

            try LoadSourcesPhase().run(ctx)

            timer.beginPhase(LexPhase.name)
            try LexPhase().run(ctx)
            timer.endPhase()

            timer.beginPhase(ParsePhase.name)
            try ParsePhase().run(ctx)
            timer.endPhase()

            let lexRecord = try #require(timer.phaseRecords.first { $0.name == LexPhase.name })
            let parseRecord = try #require(timer.phaseRecords.first { $0.name == ParsePhase.name })
            #expect(lexRecord.subRecords.contains { $0.name == "bundled-stdlib" })
            #expect(parseRecord.subRecords.contains { $0.name == "bundled-stdlib" })
        }
    }

    @Test
    func testRandomInteropUsesKotlinStdlibPlatformFilename() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])

            try LoadSourcesPhase().run(ctx)

            let bundledPaths = ctx.sourceManager.fileIDs()
                .map { ctx.sourceManager.path(of: $0) }
                .filter { $0.hasPrefix("__bundled_") }

            #expect(bundledPaths.contains("__bundled_kotlin/random/PlatformRandom.kt"))
            #expect(!bundledPaths.contains("__bundled_kotlin/random/JavaRandomInterop.kt"))
        }
    }

    /// KSP-1541: `kotlin.native` bundled sources use kotlin-native's own
    /// filenames. The two artifact shapes this replaced — a `<Type>/Stdlib.kt`
    /// or `<Type>/<Type>.kt` directory per declaration — have no counterpart
    /// upstream, so neither may come back.
    @Test
    func testNativeBundledFilenamesFollowKotlinNativeLayout() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])

            try LoadSourcesPhase().run(ctx)

            let nativePaths = ctx.sourceManager.fileIDs()
                .map { ctx.sourceManager.path(of: $0) }
                .filter { $0.hasPrefix("__bundled_kotlin/native/") }

            #expect(!nativePaths.isEmpty, "kotlin.native bundled sources should be injected.")

            for nativePath in nativePaths {
                let components = nativePath.split(separator: "/").map(String.init)
                let file = try #require(components.last)
                #expect(
                    file != "Stdlib.kt",
                    "\(nativePath) still uses the per-declaration Stdlib.kt artifact name."
                )
                if components.count >= 2 {
                    let parent = components[components.count - 2]
                    #expect(
                        file != "\(parent).kt",
                        "\(nativePath) still nests the file inside an eponymous directory."
                    )
                }
            }

            for expected in [
                "__bundled_kotlin/native/BitSet.kt",
                "__bundled_kotlin/native/Platform.kt",
                "__bundled_kotlin/native/Runtime.kt",
                "__bundled_kotlin/native/ThrowableExtensions.kt",
                "__bundled_kotlin/native/concurrent/Atomics.kt",
                "__bundled_kotlin/native/concurrent/Freezing.kt",
                "__bundled_kotlin/native/concurrent/Internal.kt",
                "__bundled_kotlin/native/concurrent/Lazy.kt",
                "__bundled_kotlin/native/concurrent/ObjectTransfer.kt",
                "__bundled_kotlin/native/ref/Cleaner.kt",
                "__bundled_kotlin/native/ref/Weak.kt",
                "__bundled_kotlin/native/ref/WeakPrivate.kt",
                "__bundled_kotlin/native/runtime/GCInfo.kt",
            ] {
                #expect(nativePaths.contains(expected), "Missing bundled source \(expected)")
            }
        }
    }
}
#endif
