#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct CompilationContextTests {
    // MARK: - CompilationContext init

    @Test
    func testCompilationContextInitStoresProperties() {
        let options = CompilerOptions(
            moduleName: "TestMod",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let sm = SourceManager()
        let diag = DiagnosticEngine()
        let interner = StringInterner()
        let ctx = CompilationContext(
            options: options,
            sourceManager: sm,
            diagnostics: diag,
            interner: interner
        )
        #expect(ctx.options.moduleName == "TestMod")
        #expect(ctx.tokens.isEmpty)
        #expect(ctx.syntaxTree == nil)
        #expect(ctx.ast == nil)
        #expect(ctx.sema == nil)
        #expect(ctx.kir == nil)
        #expect(ctx.generatedObjectPath == nil)
        #expect(ctx.generatedLLVMIRPath == nil)
        #expect(ctx.incrementalCache == nil)
        #expect(ctx.incrementalRecompileSet == nil)
        #expect(!(ctx.incrementalOutputRestored))
        #expect(ctx.phaseTimer == nil)
    }

    // MARK: - isIncremental

    @Test
    func testIsIncrementalReturnsFalseByDefault() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        #expect(!(ctx.isIncremental))
    }

    @Test
    func testIsIncrementalReturnsTrueWhenCacheSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        ctx.incrementalCache = IncrementalCompilationCache(
            cachePath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        )
        #expect(ctx.isIncremental)
    }

    // MARK: - needsRecompilation

    @Test
    func testNeedsRecompilationReturnsTrueWhenNoRecompileSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        #expect(ctx.needsRecompilation(path: "/a.kt"))
        #expect(ctx.needsRecompilation(path: "/anything.kt"))
    }

    @Test
    func testNeedsRecompilationReturnsTrueForFileInRecompileSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt", "/b.kt"])
        ctx.incrementalRecompileSet = Set(["/a.kt"])
        #expect(ctx.needsRecompilation(path: "/a.kt"))
    }

    @Test
    func testNeedsRecompilationReturnsFalseForFileNotInRecompileSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt", "/b.kt"])
        ctx.incrementalRecompileSet = Set(["/a.kt"])
        #expect(!(ctx.needsRecompilation(path: "/b.kt")))
    }

    @Test
    func testNeedsRecompilationEmptyRecompileSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        ctx.incrementalRecompileSet = Set()
        #expect(!(ctx.needsRecompilation(path: "/a.kt")))
    }

    @Test
    func testMarkIncrementalOutputRestored() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        #expect(!(ctx.incrementalOutputRestored))
        ctx.markIncrementalOutputRestored()
        #expect(ctx.incrementalOutputRestored)
    }

    // MARK: - frontendJobs

    @Test
    func testFrontendJobsDefaultIsOne() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        #expect(ctx.frontendJobs == 1)
    }

    @Test
    func testFrontendJobsReadsFromOptions() {
        let ctx = makeCompilationContext(
            inputs: ["/a.kt"],
            frontendFlags: ["jobs=4"]
        )
        #expect(ctx.frontendJobs == 4)
    }

    // MARK: - phaseTimer

    @Test
    func testPhaseTimerCanBeSet() {
        let ctx = makeCompilationContext(inputs: ["/a.kt"])
        #expect(ctx.phaseTimer == nil)
        ctx.phaseTimer = PhaseTimer()
        #expect(ctx.phaseTimer != nil)
    }
}
#endif
