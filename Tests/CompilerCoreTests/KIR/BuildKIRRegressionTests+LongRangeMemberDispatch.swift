#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testLongRangeExpressionIteratorUsesDirectDispatch() throws {
        let ctx = makeContextFromSource("""
        fun rangeIterator(): LongIterator =
            (Long.MAX_VALUE - 1L..Long.MAX_VALUE).iterator()

        fun typedRangeIterator(range: LongRange): LongIterator = range.iterator()
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        for name in ["rangeIterator", "typedRangeIterator"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: ctx.interner)
            let directIteratorCalls = body.compactMap { instruction -> SymbolID? in
                guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction,
                      sema.symbols.symbol(symbol)?.name == ctx.interner.intern("iterator")
                else { return nil }
                return symbol
            }
            #expect(directIteratorCalls.count == 1, "\(name) must call the source iterator directly")
            for symbol in directIteratorCalls {
                #expect(sema.symbols.isSourceBackedSymbol(symbol))
            }
            #expect(!body.contains { instruction in
                if case .virtualCall = instruction { return true }
                return false
            }, "A runtime range box has no Kotlin dispatch table")
        }
    }
}
#endif
