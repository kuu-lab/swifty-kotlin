#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringPassRegressionTests {

    private static nonisolated(unsafe) var _sharedFileRewriteLoweredCtx: CompilationContext?

    private func sharedFileRewriteLoweredCtx() throws -> CompilationContext {
        if let cached = Self._sharedFileRewriteLoweredCtx {
            return cached
        }

        let sources: [String] = [
            """
            package filerewrite.case0

            import java.io.File

            fun main0() {
                val f = File("/tmp/test.txt")
                f.forEachLine { line -> println(line) }
            }
            """,
            """
            package filerewrite.case1

            import java.io.File

            fun main1() {
                val f = File("/tmp/test.bin")
                f.forEachBlock { bytes, bytesRead ->
                    println(bytesRead)
                }
            }
            """,
            """
            package filerewrite.case2

            import java.io.File

            fun main2() {
                val f = File("/tmp/test.bin")
                f.forEachBlock(1024) { bytes, bytesRead ->
                    println(bytesRead)
                }
            }
            """,
            """
            package filerewrite.case3

            import java.io.File

            fun main3() {
                File("demo").walk().forEach { println(it.path) }
            }
            """,
            """
            package filerewrite.case4

            import java.io.File

            fun main4() {
                File("/tmp/test").mkdirs()
            }
            """,
            """
            package filerewrite.case5

            import java.io.File

            fun main5() {
                val f = File("/tmp/test.txt")
                val content = f.readText()
                println(content)
            }
            """,
            """
            package filerewrite.case6

            import java.io.File

            fun main6() {
                File("/tmp/test").delete()
            }
            """,
            """
            package filerewrite.case7

            import java.io.File

            fun main7() {
                val f = File("/tmp/test.txt")
                f.writeText("hello world")
            }
            """,
            """
            package filerewrite.case8

            import java.io.File

            fun main8() {
                File("/tmp/test").listFiles()
            }
            """,
            """
            package filerewrite.case9

            import java.io.File

            fun main9() {
                val f = File("/tmp/test.txt")
                val lines = f.readLines()
                println(lines.size)
            }
            """,
            """
            package filerewrite.case10

            import java.io.File

            fun main10() {
                File("/tmp/test.txt").writeText("hello")
                val content = File("/tmp/test.txt").readText()
                println(content)
            }
            """,
        ]

        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            result = ctx
        }

        let ctx = try #require(result)
        Self._sharedFileRewriteLoweredCtx = ctx
        return ctx
    }
    @Test
    func testFileForEachLineRemainsSourceBacked() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main0", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("forEachLine"))
        #expect(!callees.contains("__kk_file_forEachLine"))
    }
    @Test
    func testFileForEachBlockRewriteAddsClosureRawArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "FileForEachBlockRewrite",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        let fileExpr = arena.appendExpr(.temporary(0))
        let lambdaExpr = arena.appendExpr(.temporary(1))
        let resultExpr = arena.appendExpr(.temporary(2))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("__kk_file_new"),
                    arguments: [arena.appendExpr(.stringLiteral(interner.intern("demo.bin")), type: nil)],
                    result: fileExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("__kk_file_forEachBlock"),
                    arguments: [fileExpr, lambdaExpr],
                    result: resultExpr,
                    canThrow: true,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)

        try CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

        guard case let .function(lowered)? = module.arena.decl(declID) else {
            Issue.record("expected lowered function")
            return
        }

        let forEachBlockCall = lowered.body.compactMap { instruction -> (arguments: [KIRExprID], canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction,
                  interner.resolve(callee) == "__kk_file_forEachBlock"
            else {
                return nil
            }
            return (arguments, canThrow)
        }.first

        guard let call = forEachBlockCall else {
            Issue.record("Expected __kk_file_forEachBlock call after collection literal lowering")
            return
        }
        #expect(call.arguments.count == 3, "__kk_file_forEachBlock should receive fileRaw, fnPtr, and closureRaw")
        #expect(call.canThrow)
    }

    // STDLIB-IO-FN-016: forEachBlock source-level rewrite (default blockSize)
    @Test
    func testFileForEachBlockSourceLevelRewrite() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main1", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_forEachBlock"))
        #expect(!callees.contains("forEachBlock"))
    }
    @Test
    func testFileForEachBlockWithBlockSizeSourceLevelRewrite() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main2", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_forEachBlock_blockSize"))
        #expect(!callees.contains("forEachBlock"))
    }
    @Test
    func testFileWalkRewriteKeepsListTrackingForChainedForEach() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main3", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_walk"))
        #expect(callees.contains("kk_list_forEach"))
        #expect(!callees.contains("walk"))
    }
    @Test
    func testFileMkdirsRewrite() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main4", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_mkdirs"))
        #expect(!callees.contains("mkdirs"))
    }
    @Test
    func testFileReadTextRewrite() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main5", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_new"))
        #expect(callees.contains("__kk_file_readText"))
        #expect(!callees.contains("readText"))
    }
    @Test
    func testFileDeleteRewrite() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main6", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_delete"))
        #expect(!callees.contains("delete"))
    }
    @Test
    func testFileWriteTextRewrite() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main7", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_new"))
        #expect(callees.contains("__kk_file_writeText"))
        #expect(!callees.contains("writeText"))
    }
    @Test
    func testFileListFilesRewrite() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main8", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_listFiles"))
        #expect(!callees.contains("listFiles"))
    }
    @Test
    func testFileReadLinesRewrite() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main9", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_new"))
        #expect(callees.contains("readLines"))
        #expect(!callees.contains("__kk_file_readLines"))
    }
    @Test
    func testFileWalkRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test").walk()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileWalkRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("__kk_file_walk"))
            #expect(!callees.contains("walk"))
        }
    }

    // STDLIB-IO-PATH-FN-038: Path.useLines default variant must inject closureRaw
    @Test
    func testPathUseLinesDefaultRewriteAddsClosureRawArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "PathUseLinesDefaultRewrite",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        let pathExpr = arena.appendExpr(.temporary(0))
        let lambdaExpr = arena.appendExpr(.temporary(1))
        let resultExpr = arena.appendExpr(.temporary(2))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_path_useLines_default"),
                    arguments: [pathExpr, lambdaExpr],
                    result: resultExpr,
                    canThrow: true,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)

        try CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

        guard case let .function(lowered)? = module.arena.decl(declID) else {
            Issue.record("expected lowered function")
            return
        }

        let useLinesCall = lowered.body.compactMap { instruction -> (arguments: [KIRExprID], canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction,
                  interner.resolve(callee) == "kk_path_useLines_default"
            else { return nil }
            return (arguments, canThrow)
        }.first

        guard let call = useLinesCall else {
            Issue.record("Expected kk_path_useLines_default call after collection literal lowering")
            return
        }
        #expect(call.arguments.count == 3, "kk_path_useLines_default should receive pathRaw, fnPtr, and closureRaw")
        #expect(call.canThrow)
    }

    // STDLIB-IO-PATH-FN-038: Path.useLines(charset, block) must inject closureRaw
    @Test
    func testPathUseLinesCharsetVariantRewriteAddsClosureRawArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "PathUseLinesCharsetRewrite",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        let pathExpr = arena.appendExpr(.temporary(0))
        let charsetExpr = arena.appendExpr(.temporary(1))
        let lambdaExpr = arena.appendExpr(.temporary(2))
        let resultExpr = arena.appendExpr(.temporary(3))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_path_useLines"),
                    arguments: [pathExpr, charsetExpr, lambdaExpr],
                    result: resultExpr,
                    canThrow: true,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let declID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [declID])], arena: arena)

        try CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

        guard case let .function(lowered)? = module.arena.decl(declID) else {
            Issue.record("expected lowered function")
            return
        }

        let useLinesCall = lowered.body.compactMap { instruction -> (arguments: [KIRExprID], canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction,
                  interner.resolve(callee) == "kk_path_useLines"
            else { return nil }
            return (arguments, canThrow)
        }.first

        guard let call = useLinesCall else {
            Issue.record("Expected kk_path_useLines call after collection literal lowering")
            return
        }
        #expect(call.arguments.count == 4, "kk_path_useLines should receive pathRaw, charsetRaw, fnPtr, and closureRaw")
        #expect(call.canThrow)
    }

    @Test
    func testFileBasicOperationsIntegration() throws {
        let ctx = try sharedFileRewriteLoweredCtx()
        let module = try #require(ctx.kir)
        let mainBody = try findKIRFunctionBody(named: "main10", in: module, interner: ctx.interner)
        let callees = extractCallees(from: mainBody, interner: ctx.interner)

        #expect(callees.contains("__kk_file_new"))
        #expect(callees.contains("__kk_file_writeText"))
        #expect(callees.contains("__kk_file_readText"))
        #expect(!callees.contains("writeText"))
        #expect(!callees.contains("readText"))
    }
}
#endif
