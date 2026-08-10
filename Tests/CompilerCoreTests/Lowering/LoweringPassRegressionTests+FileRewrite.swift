#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringPassRegressionTests {
    @Test
    func testFileForEachLineRewriteAddsClosureRawArgument() {
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

        try! CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

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

    @Test
    func testFileAndPathRewriteSourceLevelLowering() throws {
        let sources = [
            """
            package sample0
            import java.io.File

            fun main0() {
                val f = File("/tmp/test.bin")
                f.forEachBlock { bytes, bytesRead ->
                    println(bytesRead)
                }
            }
            """,
            """
            package sample1
            import java.io.File

            fun main1() {
                val f = File("/tmp/test.bin")
                f.forEachBlock(1024) { bytes, bytesRead ->
                    println(bytesRead)
                }
            }
            """,
            """
            package sample2
            import java.io.File

            fun main2() {
                File("demo").walk().forEach { println(it.path) }
            }
            """,
            """
            package sample3
            import java.io.File

            fun main3() {
                File("/tmp/test").mkdirs()
            }
            """,
            """
            package sample4
            import java.io.File

            fun main4() {
                val f = File("/tmp/test.txt")
                val content = f.readText()
                println(content)
            }
            """,
            """
            package sample5
            import java.io.File

            fun main5() {
                val f = File("/tmp/test.txt")
                f.writeText("hello world")
            }
            """,
            """
            package sample6
            import java.io.File

            fun main6() {
                File("/tmp/test").listFiles()
            }
            """,
            """
            package sample7
            import java.io.File

            fun main7() {
                val f = File("/tmp/test.txt")
                val lines = f.readLines()
                println(lines.size)
            }
            """,
            """
            package sample8
            import java.io.File

            fun main8() {
                File("/tmp/test").walk()
            }
            """,
            """
            package sample9
            import kotlin.io.path.Path
            import kotlin.io.path.walk

            fun main9() {
                Path("/tmp").walk()
            }
            """,
            """
            package sample10
            import java.io.File
            import kotlin.io.FileWalkDirection

            fun main10() {
                File("/tmp/test").walk(FileWalkDirection.TOP_DOWN).toList()
            }
            """,
            """
            package sample11
            import kotlin.io.path.Path
            import kotlin.io.path.useLines

            fun main11() {
                val p = Path("/dev/null")
                val count = p.useLines { lines ->
                    lines.count()
                }
                println(count)
            }
            """,
            """
            package sample12
            import java.io.File

            fun main12() {
                File("/tmp/test.txt").writeText("hello")
                val content = File("/tmp/test.txt").readText()
                println(content)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let body = try findKIRFunctionBody(named: "main0", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_forEachBlock"))
                #expect(!callees.contains("forEachBlock"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main1", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_forEachBlock_blockSize"))
                #expect(!callees.contains("forEachBlock"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main2", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_walk"))
                #expect(callees.contains("kk_file_tree_walk_forEach"))
                #expect(!callees.contains("walk"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main3", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_mkdirs"))
                #expect(!callees.contains("mkdirs"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main4", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_new"))
                #expect(callees.contains("kk_file_readText"))
                #expect(!callees.contains("readText"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main5", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_new"))
                #expect(callees.contains("kk_file_writeText"))
                #expect(!callees.contains("writeText"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main6", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_listFiles"))
                #expect(!callees.contains("listFiles"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main7", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_new"))
                #expect(callees.contains("kk_file_readLines"))
                #expect(!callees.contains("readLines"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main8", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_walk"))
                #expect(!callees.contains("walk"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main9", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_path_walk"))
                #expect(!callees.contains("walk"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main10", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_walk_with_direction"))
                #expect(callees.contains("kk_file_tree_walk_to_list"))
                #expect(!callees.contains("walk"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main11", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_path_useLines_default"))
                #expect(!callees.contains("useLines"))
            }

            do {
                let body = try findKIRFunctionBody(named: "main12", in: module, interner: interner)
                let callees = extractCallees(from: body, interner: interner)
                #expect(callees.contains("kk_file_new"))
                #expect(callees.contains("kk_file_writeText"))
                #expect(callees.contains("kk_file_readText"))
                #expect(!callees.contains("writeText"))
                #expect(!callees.contains("readText"))
            }
        }
    }

    @Test
    func testPathUseLinesDefaultRewriteAddsClosureRawArgument() {
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

        try! CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

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

    @Test
    func testPathUseLinesCharsetVariantRewriteAddsClosureRawArgument() {
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

        try! CollectionLiteralLoweringPass().run(module: module, ctx: ctx)

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
}
#endif
