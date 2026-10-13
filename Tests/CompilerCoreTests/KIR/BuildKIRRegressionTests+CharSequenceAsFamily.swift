#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testCharSequenceAsFamilyRemainsSourceBacked() throws {
        let source = """
        fun iterable(value: CharSequence): Iterable<Char> = value.asIterable()
        fun sequence(value: CharSequence): Sequence<Char> = value.asSequence()
        """

        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        for (functionName, apiName) in [("iterable", "asIterable"), ("sequence", "asSequence")] {
            let body = try findKIRFunctionBody(named: functionName, in: module, interner: ctx.interner)
            let call = try #require(body.compactMap { instruction -> (SymbolID?, String)? in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (symbol, ctx.interner.resolve(callee))
            }.first { $0.1 == apiName })
            let symbol = try #require(call.0)
            let declaration = try #require(sema.symbols.symbol(symbol))

            #expect(sema.symbols.isSourceBackedSymbol(symbol))
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            #expect(body.filter { instruction in
                if case .call = instruction { return true }
                if case .virtualCall = instruction { return true }
                return false
            }.count == 1, "Each conversion must make only its source-backed API call")
            try expectResolvedKIRCallTargets(in: body, context: ctx)
            #expect(declaration.fqName == [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("text"),
                ctx.interner.intern(apiName),
            ])
        }
    }
}
#endif
