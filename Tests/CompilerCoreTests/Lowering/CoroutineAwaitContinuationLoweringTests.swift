@testable import CompilerCore
import Testing

@Suite
struct CoroutineAwaitContinuationLoweringTests {
    @Test
    func ordinaryInlineLambdaAwaitSuppliesOnlyAMissingContinuation() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let handle = arena.appendExpr(.intLiteral(10), type: intType)
        let continuation = arena.appendExpr(.intLiteral(20), type: intType)
        let awaitCallee = interner.intern("kk_kxmini_async_await")
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 1),
            name: interner.intern("inlineLambda"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(callee: awaitCallee, arguments: [handle],
                      result: nil, canThrow: false),
                .call(callee: awaitCallee, arguments: [handle, continuation],
                      result: nil, canThrow: false),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: true
        )
        let declaration = arena.appendDecl(.function(function))
        let module = KIRModule(files: [], arena: arena)
        let ctx = makeKIRContext(interner: interner)
        try CoroutineLoweringPass().run(module: module, ctx: ctx)
        let lowered = try #require(arena.decl(declaration)?.function)
        let arguments = lowered.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  callee == awaitCallee else { return nil }
            return arguments
        }
        #expect(arguments.count == 2)
        let first = try #require(arguments.first)
        #expect(first.count == 2)
        #expect(first.first == handle)
        let fallback = try #require(first.last)
        #expect(arena.expr(fallback) == .intLiteral(0))
        #expect(arguments.last == [handle, continuation])
    }
}
