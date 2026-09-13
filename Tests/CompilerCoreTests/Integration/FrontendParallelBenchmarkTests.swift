#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Multi-file compile benchmarks for frontend parallelization (P5-61)

// Serialize the suite so concurrent benchmark cases do not distort timing through CPU contention.
@Suite(.serialized)
struct FrontendParallelBenchmarkTests {
    // MARK: - Helpers

    /// Generate N Kotlin source files with varied declarations.
    private func generateSources(count: Int) -> [String] {
        (0 ..< count).map { i in
            """
            package bench\(i)

            import kotlin.collections.*

            class Widget\(i)(val id: Int, val label: String) {
                fun describe(): String = "Widget(\(i))"
                fun compute(x: Int): Int = x * \(i + 1)
            }

            interface Renderable\(i) {
                fun render(): String
            }

            object Registry\(i) {
                val items: Int = \(i)
            }

            fun helper\(i)(a: Int, b: Int): Int = a + b + \(i)
            fun transform\(i)(s: String): String = s
            """
        }
    }

    /// Run frontend with the given sources and jobs count, returning elapsed time.
    private func runFrontendTimed(
        sources: [String],
        jobs: Int
    ) throws -> (ctx: CompilationContext, elapsed: Double) {
        var paths: [String] = []
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        for (index, source) in sources.enumerated() {
            let fileURL = tempDir.appendingPathComponent("input\(index).kt")
            try source.write(to: fileURL, atomically: true, encoding: .utf8)
            paths.append(fileURL.path)
        }

        let flags = ["jobs=\(jobs)"]
        let ctx = makeCompilationContext(inputs: paths, frontendFlags: flags)

        let start = Date()
        try LoadSourcesPhase().run(ctx)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        let elapsed = Date().timeIntervalSince(start)

        return (ctx, elapsed)
    }

    // MARK: - Correctness: per-file frontend results

    @Test func testPerFileFrontendResultsPopulatedForAllFiles() throws {
        let sources = generateSources(count: 5)
        let (ctx, _) = try runFrontendTimed(sources: sources, jobs: 1)

        // 5 user files + auto-loaded .kt files + residual bundled stdlib files
        let totalFileCount = ctx.tokensByFile.count
        #expect(totalFileCount > 5, "Expected more than 5 files (user files + bundled stdlib)")
        #expect(ctx.syntaxTrees.count == totalFileCount, "Expected syntax trees for all files")
        let ast = try #require(ctx.ast)
        #expect(ast.sortedFiles.count == totalFileCount, "Expected AST files for all files")

        for (fileID, tokens) in ctx.tokensByFile {
            #expect(!tokens.isEmpty, "Tokens should be populated for file \(fileID.rawValue)")
        }
    }

    @Test func testPerFileFrontendResultsPopulatedInParallelMode() throws {
        let sources = generateSources(count: 5)
        let (ctx, _) = try runFrontendTimed(sources: sources, jobs: 4)

        // 5 user files + auto-loaded .kt files + residual bundled stdlib files
        let totalFileCount = ctx.tokensByFile.count
        #expect(totalFileCount > 5, "Expected more than 5 files in parallel mode (user files + bundled stdlib)")
        #expect(ctx.syntaxTrees.count == totalFileCount, "Expected syntax trees for all files in parallel mode")
        let ast = try #require(ctx.ast)
        #expect(ast.sortedFiles.count == totalFileCount, "Expected AST files for all files in parallel mode")

        for (fileID, tokens) in ctx.tokensByFile {
            #expect(!tokens.isEmpty, "Tokens should be populated for file \(fileID.rawValue)")
        }
    }

    // MARK: - Deterministic output ordering

    @Test func testParallelOutputIsDeterministic() throws {
        let sources = generateSources(count: 20)

        // Run multiple times with jobs=4 and verify identical AST structure.
        var previousDeclNames: [String]?

        for iteration in 0 ..< 3 {
            let (ctx, _) = try runFrontendTimed(sources: sources, jobs: 4)
            let ast = try #require(ctx.ast, "AST should be non-nil (iteration \(iteration))")

            // Collect all declaration names in file order.
            let declNames: [String] = ast.sortedFiles.flatMap { file in
                file.topLevelDecls.compactMap { declID -> String? in
                    guard let decl = ast.arena.decl(declID) else { return nil }
                    return topLevelDeclName(decl, interner: ctx.interner)
                }
            }

            if let prev = previousDeclNames {
                #expect(
                    prev == declNames,
                    "Declaration order must be deterministic across parallel runs (iteration \(iteration))"
                )
            }
            previousDeclNames = declNames
        }
    }

    // MARK: - Diagnostic order stability

    @Test func testDiagnosticOrderIsStableAcrossParallelRuns() throws {
        // Intentionally include some files with parse warnings/issues.
        var sources = generateSources(count: 10)
        // Add a file with a trailing comma to trigger a diagnostic.
        sources.append("""
        package diag
        fun broken(a: Int,): Int = a
        """)

        var previousDiagCodes: [String]?

        for iteration in 0 ..< 3 {
            let (ctx, _) = try runFrontendTimed(sources: sources, jobs: 4)

            let diagCodes = ctx.diagnostics.diagnostics.map(\.code)

            if let prev = previousDiagCodes {
                #expect(
                    prev == diagCodes,
                    "Diagnostic order must be stable across parallel runs (iteration \(iteration))"
                )
            }
            previousDiagCodes = diagCodes
        }
    }

    // MARK: - Benchmarks: 10 / 50 / 100 files

    @Test(arguments: [10, 50, 100])
    func testBenchmarkFrontendFiles(fileCount: Int) throws {
        let sources = generateSources(count: fileCount)
        let (seqCtx, seqTime) = try runFrontendTimed(sources: sources, jobs: 1)
        let (parCtx, parTime) = try runFrontendTimed(sources: sources, jobs: 4)

        let seqAST = try #require(seqCtx.ast)
        let parAST = try #require(parCtx.ast)
        #expect(seqAST.sortedFiles.count == parAST.sortedFiles.count, "File count must match")
        #expect(seqAST.declarationCount == parAST.declarationCount, "Declaration count must match")

        let speedup = seqTime / max(parTime, 0.000001)

        print("[Benchmark \(fileCount) files] sequential=\(String(format: "%.4f", seqTime))s parallel(4)=\(String(format: "%.4f", parTime))s speedup=\(String(format: "%.2f", speedup))x")
    }

    // MARK: - frontendJobs parsing

    @Test func testFrontendJobsParsing() {
        let cases: [(flags: [String], expected: Int, note: String)] = [
            (["jobs=4"], 4, "explicit jobs=4"),
            ([], 1, "Default should be 1 (sequential)"),
            (["jobs=0"], 1, "jobs=0 should fall back to 1"),
            (["jobs=1"], 1, "jobs=1 should be sequential"),
            (["other-flag", "jobs=8"], 8, "jobs= after an unrelated flag"),
        ]

        for (flags, expected, note) in cases {
            let options = CompilerOptions(
                moduleName: "M", inputs: [], outputPath: "/tmp/out", emit: .kirDump,
                target: defaultTargetTriple(), frontendFlags: flags
            )
            #expect(options.frontendJobs == expected, "\(note): flags=\(flags)")
        }
    }

    // MARK: - Sequential vs parallel AST equivalence

    @Test func testSequentialAndParallelProduceSameAST() throws {
        let sources = generateSources(count: 15)

        let (seqCtx, _) = try runFrontendTimed(sources: sources, jobs: 1)
        let (parCtx, _) = try runFrontendTimed(sources: sources, jobs: 4)

        let seqAST = try #require(seqCtx.ast)
        let parAST = try #require(parCtx.ast)

        #expect(seqAST.sortedFiles.count == parAST.sortedFiles.count)
        #expect(seqAST.declarationCount == parAST.declarationCount)

        // Verify file order matches.
        for (seqFile, parFile) in zip(seqAST.sortedFiles, parAST.sortedFiles) {
            #expect(seqFile.fileID == parFile.fileID, "File order must be deterministic")
            #expect(
                seqFile.topLevelDecls.count == parFile.topLevelDecls.count,
                "Declaration count must match for file \(seqFile.fileID.rawValue)"
            )

            // Verify declaration names match in order.
            let seqNames = seqFile.topLevelDecls.compactMap { declID -> String? in
                guard let decl = seqAST.arena.decl(declID) else { return nil }
                return topLevelDeclName(decl, interner: seqCtx.interner)
            }
            let parNames = parFile.topLevelDecls.compactMap { declID -> String? in
                guard let decl = parAST.arena.decl(declID) else { return nil }
                return topLevelDeclName(decl, interner: parCtx.interner)
            }
            #expect(
                seqNames == parNames,
                "Declaration names must match between sequential and parallel for file \(seqFile.fileID.rawValue)"
            )
        }
    }

    private func topLevelDeclName(_ decl: Decl, interner: StringInterner) -> String? {
        switch decl {
        case let .classDecl(c): interner.resolve(c.name)
        case let .interfaceDecl(i): interner.resolve(i.name)
        case let .objectDecl(o): interner.resolve(o.name)
        case let .funDecl(f): interner.resolve(f.name)
        default: nil
        }
    }
}
#endif
