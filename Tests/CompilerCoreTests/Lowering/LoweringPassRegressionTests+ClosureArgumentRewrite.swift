#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringPassRegressionTests {

    // STDLIB-IO-PATH-FN-038: Path.useLines default variant must inject closureRaw
    @Test
    func testPathUseLinesDefaultRewriteAddsClosureRawArgument() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let ctx = makeKIRContext(
            moduleName: "PathUseLinesDefaultRewrite",
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

        let lowered = try requireTestValue(module.arena.decl(declID)?.function, "expected lowered function")

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
        let ctx = makeKIRContext(
            moduleName: "PathUseLinesCharsetRewrite",
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

        let lowered = try requireTestValue(module.arena.decl(declID)?.function, "expected lowered function")

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
