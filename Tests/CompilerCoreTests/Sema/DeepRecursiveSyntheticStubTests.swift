#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DeepRecursiveSyntheticStubTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testDeepRecursiveSyntheticTypesAndMembersAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let functionFQName = ["kotlin", "DeepRecursiveFunction"].map { interner.intern($0) }
        let scopeFQName = ["kotlin", "DeepRecursiveScope"].map { interner.intern($0) }

        let functionSymbol = try #require(sema.symbols.lookup(fqName: functionFQName))
        let scopeSymbol = try #require(sema.symbols.lookup(fqName: scopeFQName))

        #expect(sema.symbols.symbol(functionSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(scopeSymbol)?.kind == .class)
        #expect(sema.types.nominalTypeParameterSymbols(for: functionSymbol).count == 2)
        #expect(sema.types.nominalTypeParameterSymbols(for: scopeSymbol).count == 2)

        let functionInit = try #require(sema.symbols.lookup(fqName: functionFQName + [interner.intern("<init>")]))
        #expect(sema.symbols.externalLinkName(for: functionInit) == "kk_deep_recursive_function_new")

        let invokeSymbol = try #require(sema.symbols.lookup(fqName: functionFQName + [interner.intern("invoke")]))
        #expect(sema.symbols.externalLinkName(for: invokeSymbol) == "kk_deep_recursive_function_invoke")
        #expect(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)

        let functionCallRecursive = try #require(
            sema.symbols.lookup(fqName: functionFQName + [interner.intern("callRecursive")])
        )
        #expect(
            sema.symbols.externalLinkName(for: functionCallRecursive) == "kk_deep_recursive_function_callRecursive"
        )

        let scopeCallRecursive = try #require(
            sema.symbols.lookup(fqName: scopeFQName + [interner.intern("callRecursive")])
        )
        #expect(
            sema.symbols.externalLinkName(for: scopeCallRecursive) == "kk_deep_recursive_scope_callRecursive"
        )
    }

    @Test func testDeepRecursiveFunctionResolvesInSource() throws {
        let source = """
        class Node(val next: Node?)

        fun makeDepth(): DeepRecursiveFunction<Node?, Int> {
            val depth: DeepRecursiveFunction<Node?, Int> = DeepRecursiveFunction<Node?, Int> {
                if (it == null) 0 else callRecursive(it.next) + 1
            }
            return depth
        }

        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnosticsEmpty = ctx.diagnostics.diagnostics.isEmpty
            #expect(diagnosticsEmpty)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let constructorCall = try #require(firstExprID(in: ast) { exprID, _ in
                guard let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else {
                    return false
                }
                return sema.symbols.externalLinkName(for: chosen) == "kk_deep_recursive_function_new"
            })
            let constructorCallee = try #require(sema.bindings.callBinding(for: constructorCall)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: constructorCallee) == "kk_deep_recursive_function_new")

        }
    }
}
#endif
