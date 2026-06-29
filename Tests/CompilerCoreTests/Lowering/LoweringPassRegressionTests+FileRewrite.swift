#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringPassRegressionTests {
    @Test
    func testFileForEachLineRewriteAddsClosureRawArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "FileForEachLineRewrite",
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
                    callee: interner.intern("kk_file_new"),
                    arguments: [arena.appendExpr(.stringLiteral(interner.intern("demo.txt")), type: nil)],
                    result: fileExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                // The KIR builder emits a .call with the already-rewritten callee
                // name (from externalLinkName) rather than a .virtualCall.
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_file_forEachLine"),
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

        let forEachLineCall = lowered.body.compactMap { instruction -> (arguments: [KIRExprID], canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction,
                  interner.resolve(callee) == "kk_file_forEachLine"
            else {
                return nil
            }
            return (arguments, canThrow)
        }.first

        guard let call = forEachLineCall else {
            Issue.record("Expected kk_file_forEachLine call after collection literal lowering")
            return
        }
        #expect(call.arguments.count == 3, "kk_file_forEachLine should receive fileRaw, fnPtr, and closureRaw")
        #expect(call.canThrow)
    }

    // STDLIB-IO-FN-016: forEachBlock KIR rewrite adds closureRaw argument
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
                    callee: interner.intern("kk_file_new"),
                    arguments: [arena.appendExpr(.stringLiteral(interner.intern("demo.bin")), type: nil)],
                    result: fileExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: nil,
                    callee: interner.intern("kk_file_forEachBlock"),
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
                  interner.resolve(callee) == "kk_file_forEachBlock"
            else {
                return nil
            }
            return (arguments, canThrow)
        }.first

        guard let call = forEachBlockCall else {
            Issue.record("Expected kk_file_forEachBlock call after collection literal lowering")
            return
        }
        #expect(call.arguments.count == 3, "kk_file_forEachBlock should receive fileRaw, fnPtr, and closureRaw")
        #expect(call.canThrow)
    }

    // STDLIB-IO-FN-016: forEachBlock source-level rewrite (default blockSize)
    @Test
    func testFileForEachBlockSourceLevelRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            val f = File("/tmp/test.bin")
            f.forEachBlock { bytes, bytesRead ->
                println(bytesRead)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileForEachBlock", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_forEachBlock"))
            #expect(!callees.contains("forEachBlock"))
        }
    }

    // STDLIB-IO-FN-016: forEachBlock with explicit blockSize
    @Test
    func testFileForEachBlockWithBlockSizeSourceLevelRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            val f = File("/tmp/test.bin")
            f.forEachBlock(1024) { bytes, bytesRead ->
                println(bytesRead)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileForEachBlockSize", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_forEachBlock_blockSize"))
            #expect(!callees.contains("forEachBlock"))
        }
    }

    @Test
    func testFileWalkRewriteKeepsListTrackingForChainedForEach() throws {
        let source = """
        import java.io.File

        fun main() {
            File("demo").walk().forEach { println(it.path) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileWalkRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_walk"))
            #expect(callees.contains("kk_file_tree_walk_forEach"))
            #expect(!callees.contains("walk"))
        }
    }

    @Test
    func testFileMkdirsRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test").mkdirs()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileMkdirsRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_mkdirs"))
            #expect(!callees.contains("mkdirs"))
        }
    }

    @Test
    func testFileReadTextRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            val f = File("/tmp/test.txt")
            val content = f.readText()
            println(content)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileReadTextRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_new"))
            #expect(callees.contains("kk_file_readText"))
            #expect(!callees.contains("readText"))
        }
    }

    @Test
    func testFileDeleteRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test").delete()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileDeleteRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_delete"))
            #expect(!callees.contains("delete"))
        }
    }

    @Test
    func testFileWriteTextRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            val f = File("/tmp/test.txt")
            f.writeText("hello world")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileWriteTextRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_new"))
            #expect(callees.contains("kk_file_writeText"))
            #expect(!callees.contains("writeText"))
        }
    }

    @Test
    func testFileListFilesRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test").listFiles()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileListFilesRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_listFiles"))
            #expect(!callees.contains("listFiles"))
        }
    }

    @Test
    func testFileReadLinesRewrite() throws {
        let source = """
        import java.io.File

        fun main() {
            val f = File("/tmp/test.txt")
            val lines = f.readLines()
            println(lines.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileReadLinesRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_new"))
            #expect(callees.contains("kk_file_readLines"))
            #expect(!callees.contains("readLines"))
        }
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

            #expect(callees.contains("kk_file_walk"))
            #expect(!callees.contains("walk"))
        }
    }

    // STDLIB-IO-PATH-FN-039: Path.walk() must lower to kk_path_walk
    @Test
    func testPathWalkRewrite() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.walk

        fun main() {
            Path("/tmp").walk()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "PathWalkRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_path_walk"), "Path.walk() must lower to kk_path_walk")
            #expect(!callees.contains("walk"))
        }
    }

    // STDLIB-IO-PATH-FN-039: File.walk(direction:) must lower to kk_file_walk_with_direction
    @Test
    func testFileWalkWithDirectionRewrite() throws {
        let source = """
        import java.io.File
        import kotlin.io.FileWalkDirection

        fun main() {
            File("/tmp/test").walk(FileWalkDirection.TOP_DOWN).toList()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileWalkDirectionRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_walk_with_direction"), "walk(direction:) must lower to kk_file_walk_with_direction")
            #expect(callees.contains("kk_file_tree_walk_to_list"), "chained toList() on walk(direction:) result must be rewritten")
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

    // STDLIB-IO-PATH-FN-038: end-to-end source rewrite lowers useLines to kk_path_useLines_default
    @Test
    func testPathUseLinesSourceRewrite() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines

        fun main() {
            val p = Path("/dev/null")
            val count = p.useLines { lines ->
                lines.count()
            }
            println(count)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "PathUseLinesRewrite", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_path_useLines_default"), "useLines without charset should lower to kk_path_useLines_default")
            #expect(!callees.contains("useLines"), "useLines callee should be fully rewritten")
        }
    }

    @Test
    func testFileBasicOperationsIntegration() throws {
        let source = """
        import java.io.File

        fun main() {
            File("/tmp/test.txt").writeText("hello")
            val content = File("/tmp/test.txt").readText()
            println(content)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "FileBasicOperations", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: mainBody, interner: ctx.interner)

            #expect(callees.contains("kk_file_new"))
            #expect(callees.contains("kk_file_writeText"))
            #expect(callees.contains("kk_file_readText"))
            #expect(!callees.contains("writeText"))
            #expect(!callees.contains("readText"))
        }
    }

}
#endif
