#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringPassRegressionTests {

    // STDLIB-IO-FN-040: BufferedReader.useLines must inject closureRaw.
    //
    // CLEANUP-STUB-115 removed the parallel `kk_path_useLines`/`kk_path_useLines_default`
    // coverage this file used to carry (`kotlin.io.path.Path`'s synthetic stubs were
    // deleted entirely, so those callees no longer reach `rewriteFileCall`). This is the
    // BufferedReader branch of the same closureRaw-injection logic in
    // `CollectionLiteralLoweringPass+CallRewriteFile.swift`, which previously had no
    // Lowering-pass-level coverage of its own (only Runtime-level cdecl tests).
    @Test
    func testBufferedReaderUseLinesRewriteAddsClosureRawArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let ctx = makeKIRContext(
            moduleName: "BufferedReaderUseLinesRewrite",
            interner: interner
        )

        let readerExpr = arena.appendExpr(.temporary(0))
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
                    callee: interner.intern("__kk_buffered_reader_useLines"),
                    arguments: [readerExpr, lambdaExpr],
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

        let lowered = try requireTestValue(module.arena.decl(declID)?.function, "expected lowered function")

        let useLinesCall = lowered.body.compactMap { instruction -> (arguments: [KIRExprID], canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction,
                  interner.resolve(callee) == "__kk_buffered_reader_useLines"
            else { return nil }
            return (arguments, canThrow)
        }.first

        guard let call = useLinesCall else {
            Issue.record("Expected __kk_buffered_reader_useLines call after collection literal lowering")
            return
        }
        #expect(call.arguments.count == 3, "__kk_buffered_reader_useLines should receive receiverRaw, fnPtr, and closureRaw")
        #expect(call.canThrow)
    }

    // STDLIB-IO-FN-017: BufferedReader.forEachLine must inject closureRaw.
    @Test
    func testBufferedReaderForEachLineRewriteAddsClosureRawArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let ctx = makeKIRContext(
            moduleName: "BufferedReaderForEachLineRewrite",
            interner: interner
        )

        let readerExpr = arena.appendExpr(.temporary(0))
        let actionExpr = arena.appendExpr(.temporary(1))
        let resultExpr = arena.appendExpr(.temporary(2))
        let fn = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("__kk_buffered_reader_forEachLine"),
                    arguments: [readerExpr, actionExpr],
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

        let lowered = try requireTestValue(module.arena.decl(declID)?.function, "expected lowered function")

        let forEachLineCall = lowered.body.compactMap { instruction -> (arguments: [KIRExprID], canThrow: Bool)? in
            guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction,
                  interner.resolve(callee) == "__kk_buffered_reader_forEachLine"
            else { return nil }
            return (arguments, canThrow)
        }.first

        guard let call = forEachLineCall else {
            Issue.record("Expected __kk_buffered_reader_forEachLine call after collection literal lowering")
            return
        }
        #expect(call.arguments.count == 3, "__kk_buffered_reader_forEachLine should receive receiverRaw, fnPtr, and closureRaw")
        #expect(call.canThrow)
    }
}
#endif
