#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    /// KSP-1000: the identity extension remains a source-backed inline call and
    /// never lowers to an iterator runtime bridge.
    @Test
    func testIteratorIdentityExtensionIsSourceBackedInlineWithoutRuntimeCallee() throws {
        let source = """
        fun <T> identity(iterator: Iterator<T>): Iterator<T> =
            iterator.iterator()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "identity", in: module, interner: ctx.interner)
            let iteratorCalls = body.compactMap { instruction -> (SymbolID?, String)? in
                guard case let .call(symbol, callee, _, _, _, _, _, _) = instruction else {
                    return nil
                }
                return (symbol, ctx.interner.resolve(callee))
            }.filter { $0.1 == "iterator" }
            #expect(iteratorCalls.count == 1, "Expected one identity call, got: \(iteratorCalls)")

            let sema = try #require(ctx.sema)
            let (iteratorSymbol, _) = try #require(iteratorCalls.first)
            let symbol = try #require(iteratorSymbol)
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
            #expect(sema.symbols.symbol(symbol)?.flags.contains(.inlineFunction) == true)
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)

            let callees = extractCallees(from: body, interner: ctx.interner)
            let virtualCallees = extractVirtualCallees(from: body, interner: ctx.interner)
            let allCallees = callees + virtualCallees
            #expect(
                allCallees.allSatisfy { !$0.hasPrefix("kk_iterator_") },
                "Iterator.iterator must not lower to an iterator runtime callee, got: \(allCallees)"
            )
        }
    }
}
#endif
