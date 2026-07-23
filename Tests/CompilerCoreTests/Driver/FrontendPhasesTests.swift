#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FrontendPhasesTests {
    // MARK: - LoadSourcesPhase

    @Test
    func testLoadSourcesWithNoInputsEmitsDiagnosticAndThrows() {
        let ctx = makeCompilationContext(inputs: [])
        #expect(throws: (any Error).self, "LoadSourcesPhase should throw when no inputs") { try LoadSourcesPhase().run(ctx) }
        assertHasDiagnostic("KSWIFTK-SOURCE-0001", in: ctx)
    }

    @Test
    func testLoadSourcesWithMissingFileEmitsDiagnosticAndThrows() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kt")
            .path
        let ctx = makeCompilationContext(inputs: [missingPath])
        #expect(throws: (any Error).self, "LoadSourcesPhase should throw for missing file") { try LoadSourcesPhase().run(ctx) }
        assertHasDiagnostic("KSWIFTK-SOURCE-0002", in: ctx)
    }

    @Test
    func testLoadSourcesWithValidFileSucceeds() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            #expect(throws: Never.self) { try LoadSourcesPhase().run(ctx) }
            #expect(!(ctx.diagnostics.hasError), "No errors expected for valid input file")
            #expect(!(ctx.sourceManager.fileIDs().isEmpty), "Source manager should have loaded the file")
        }
    }

    @Test
    func testLoadSourcesRespectsIncludeStdlibOption() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let withoutStdlib = makeCompilationContext(inputs: [path], includeStdlib: false)
            #expect(throws: Never.self) { try LoadSourcesPhase().run(withoutStdlib) }
            #expect(
                withoutStdlib.sourceManager.fileIDs().allSatisfy {
                    !withoutStdlib.sourceManager.path(of: $0).hasPrefix("__bundled_")
                },
                "--no-stdlib should not inject bundled sources"
            )

            let withStdlib = makeCompilationContext(inputs: [path], includeStdlib: true)
            #expect(throws: Never.self) { try LoadSourcesPhase().run(withStdlib) }
            #expect(
                withStdlib.sourceManager.fileIDs().contains {
                    withStdlib.sourceManager.path(of: $0).hasPrefix("__bundled_")
                },
                "stdlib-enabled compilation should inject bundled sources"
            )
        }
    }

    @Test
    func testLoadSourcesSkipsDuplicatePaths() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path, path])
            #expect(throws: Never.self) { try LoadSourcesPhase().run(ctx) }
            // File should be loaded only once — verify by loading a single file and comparing
            let singleCtx = makeCompilationContext(inputs: [path])
            #expect(throws: Never.self) { try LoadSourcesPhase().run(singleCtx) }
            #expect(ctx.sourceManager.fileIDs().count == singleCtx.sourceManager.fileIDs().count, "Duplicate paths should be loaded only once (+ bundled stdlib)")
        }
    }

    @Test
    func testBundledStdlibMissingResourcePathEmits0101AndThrows() {
        let ctx = makeCompilationContext(inputs: [])
        #expect(throws: (any Error).self) {
            try LoadSourcesPhase().injectBundledStdlib(into: ctx, resourcePath: nil)
        }
        assertHasDiagnostic("KSWIFTK-SOURCE-0101", in: ctx)
    }

    @Test
    func testBundledStdlibMissingStdlibDirEmits0101AndThrows() {
        let ctx = makeCompilationContext(inputs: [])
        let resourcePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer { try? FileManager.default.removeItem(atPath: resourcePath) }
        #expect(throws: (any Error).self) {
            try LoadSourcesPhase().injectBundledStdlib(into: ctx, resourcePath: resourcePath)
        }
        assertHasDiagnostic("KSWIFTK-SOURCE-0101", in: ctx)
    }

    @Test
    func testBundledStdlibUnreadableSourceEmits0102AndThrows() throws {
        let ctx = makeCompilationContext(inputs: [])
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let stdlibDir = tempDir.appendingPathComponent("Stdlib")
        try FileManager.default.createDirectory(at: stdlibDir, withIntermediateDirectories: true)
        // Use a directory named `.kt` instead of a real file; `FileManager.contents(atPath:)`
        // returns nil for directories even when running as root, so this failure path is
        // independent of the current user/permission bits.
        let unreadablePath = stdlibDir.appendingPathComponent("test.kt")
        try FileManager.default.createDirectory(at: unreadablePath, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        #expect(throws: (any Error).self) {
            try LoadSourcesPhase().injectBundledStdlib(into: ctx, resourcePath: tempDir.path)
        }
        assertHasDiagnostic("KSWIFTK-SOURCE-0102", in: ctx)
    }

    // MARK: - LexPhase

    @Test
    func testLexPhasePopulatesTokens() throws {
        let source = "fun main() { println(42) }"
        let ctx = makeContextFromSource(source)
        #expect(throws: Never.self) { try LexPhase().run(ctx) }
        #expect(!(ctx.tokens.isEmpty), "LexPhase should populate ctx.tokens")
    }

    @Test
    func testLexPhasePopulatesTokensByFile() throws {
        let source = "fun main() {}"
        let ctx = makeContextFromSource(source)
        #expect(throws: Never.self) { try LexPhase().run(ctx) }
        let (_, fileTokens) = try #require(ctx.tokensByFile.first)
        #expect(!(fileTokens.isEmpty), "LexPhase should populate per-file tokens")
    }

    @Test
    func testLexPhaseProducesEOFTokenLast() throws {
        let source = "val x = 1"
        let ctx = makeContextFromSource(source)
        #expect(throws: Never.self) { try LexPhase().run(ctx) }
        #expect(!(ctx.tokens.isEmpty))
        let fileTokens = ctx.tokensByFile.first?.1
        #expect(fileTokens?.last?.kind == .eof, "Last token in file should be EOF")
    }

    @Test
    func testIncrementalFrontendLexesParsesAndBuildsOnlyRecompiledFiles() throws {
        try withTemporaryFiles(contents: [
            "fun kept(): String = \"kept\"",
            "fun oldChanged(): String = kept()",
        ]) { paths in
            let initialCtx = makeCompilationContext(inputs: paths)
            try runFrontend(initialCtx)
            let cachedState = try #require(IncrementalFrontendState(context: initialCtx, buildConfigurationHash: "test"))

            try "fun newChanged(): String = kept()".write(toFile: paths[1], atomically: true, encoding: .utf8)

            let incrementalCtx = makeCompilationContext(inputs: paths)
            try LoadSourcesPhase().run(incrementalCtx)
            incrementalCtx.interner.preload(cachedState.internerValues)
            incrementalCtx.setIncrementalRecompileSet([paths[1]])
            incrementalCtx.installIncrementalFrontendState(cachedState)

            try LexPhase().run(incrementalCtx)
            // FileIDs 0-7 = bundled stdlib (6 auto-loaded + 2 residual), FileID 8 = kept, FileID 9 = changed
            let changedFileID = FileID(rawValue: Int32(incrementalCtx.sourceManager.fileIDs().count - 1))
            #expect(incrementalCtx.tokensByFile.map(\.0) == [changedFileID])

            try ParsePhase().run(incrementalCtx)
            #expect(incrementalCtx.syntaxTrees.map(\.0) == [changedFileID])

            try BuildASTPhase().run(incrementalCtx)
            let ast = try #require(incrementalCtx.ast)
            let allFileIDs = (0 ..< incrementalCtx.sourceManager.fileIDs().count).map { FileID(rawValue: Int32($0)) }
            #expect(ast.files.map(\.fileID) == allFileIDs)
            #expect(Set(ast.activeDeclsByFileRawID.keys) == Set(allFileIDs.map(\.rawValue)))

            let topLevelNames = ast.files.flatMap(\.topLevelDecls).compactMap { declID -> String? in
                guard let decl = ast.arena.decl(declID), case let .funDecl(funDecl) = decl else {
                    return nil
                }
                return incrementalCtx.interner.resolve(funDecl.name)
            }
            #expect(topLevelNames.contains("kept"))
            #expect(topLevelNames.contains("newChanged"))
            #expect(!(topLevelNames.contains("oldChanged")))

            try SemaPhase().run(incrementalCtx)
            #expect(
                !(incrementalCtx.diagnostics.hasError),
                Comment(rawValue: "Unexpected diagnostics: \(incrementalCtx.diagnostics.diagnostics)")
            )
        }
    }

    // MARK: - ParsePhase

    @Test
    func testParsePhasePopulatesSyntaxTrees() throws {
        let source = "fun main() {}"
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        #expect(throws: Never.self) { try ParsePhase().run(ctx) }
        #expect(!(ctx.syntaxTrees.isEmpty), "ParsePhase should populate syntaxTrees")
    }

    @Test
    func testParsePhasePopulatesSyntaxArenaPerFile() throws {
        let source = "fun main() {}"
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        #expect(throws: Never.self) { try ParsePhase().run(ctx) }
        let (_, arena, root) = try #require(ctx.syntaxTrees.first)
        #expect(arena.node(root).kind == .kotlinFile, "ParsePhase should store each file's SyntaxArena and root")
    }

    @Test
    func testParsePhaseHandlesValidDeclarations() throws {
        let source = """
        class Foo {
            fun bar(): Int = 42
        }
        """
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        #expect(throws: Never.self) { try ParsePhase().run(ctx) }
        #expect(!(ctx.diagnostics.hasError), "Valid Kotlin source should parse without errors")
    }

    // MARK: - BuildASTPhase

    @Test
    func testBuildASTProducesASTModule() throws {
        let source = "fun main() {}"
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        #expect(throws: Never.self) { try BuildASTPhase().run(ctx) }
        #expect(ctx.ast != nil, "BuildASTPhase should produce an ASTModule in ctx.ast")
    }

    @Test
    func testBuildASTPopulatesTopLevelDecls() throws {
        let source = """
        fun foo() {}
        fun bar() {}
        """
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        let ast = try #require(ctx.ast)
        let totalDecls = ast.sortedFiles.reduce(0) { $0 + $1.topLevelDecls.count }
        #expect(totalDecls >= 2, "Should have at least 2 top-level declarations")
    }

    @Test
    func testBuildASTHandlesScriptMode() throws {
        let source = "val x = 42"
        let ctx = makeContextFromSource(source)
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        // Script mode may produce diagnostics but should not crash
        #expect(throws: Never.self) { try BuildASTPhase().run(ctx) }
        #expect(ctx.ast != nil, "BuildASTPhase should produce an ASTModule even for script-mode source")
    }

    // MARK: - Full frontend pipeline

    @Test
    func testFullFrontendPipelineSucceeds() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        fun main() {
            val result = add(1, 2)
        }
        """
        let ctx = makeContextFromSource(source)
        #expect(throws: Never.self) { try runFrontend(ctx) }
        #expect(ctx.ast != nil, "Full frontend pipeline should produce an ASTModule")
        #expect(!(ctx.diagnostics.hasError), "Valid Kotlin source should not produce errors")
    }
}
#endif
