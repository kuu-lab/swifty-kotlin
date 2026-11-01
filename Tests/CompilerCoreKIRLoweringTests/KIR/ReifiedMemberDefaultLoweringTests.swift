@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ReifiedMemberDefaultLoweringTests {
    @Test
    func memberAndDefaultStubForwardMatchingTokenPairs() throws {
        let ctx = makeContextFromSource("""
        enum class E { A, B }
        class Factory<C> {
            inline fun <reified T : Enum<T>> choice(noinline value: () -> Int = { 7 }): Array<T> = enumValues<T>()
            inline fun <reified A, reified B> ordered(value: Int = 0): String = A::class.simpleName + B::class.simpleName
            inline fun <reified T> String.extensionName(value: Int = 0): String = T::class.simpleName ?: "?"
        }
        fun direct(factory: Factory<String>) = factory.choice<E>({ 9 })
        fun defaults(factory: Factory<String>) = factory.choice<E>()
        fun orderedProbe(factory: Factory<String>) = factory.ordered<String, Int>()
        """)
        try runToKIR(ctx)
        try #require(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)

        for (name, leadingCount, tokenCount) in [("choice", 2, 2), ("ordered", 2, 4), ("extensionName", 3, 2)] {
            let member = try findKIRFunction(named: name, in: module, interner: ctx.interner)
            let signature = try #require(sema.symbols.functionSignature(for: member.symbol))
            #expect(signature.classTypeParameterCount == 1)
            let hiddenSymbols = signature.reifiedTypeParameterIndices.sorted().flatMap { index in
                let parameter = signature.typeParameterSymbols[index]
                return [SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: parameter),
                        SyntheticSymbolScheme.reifiedKTypeSymbol(for: parameter)]
            }
            #expect(hiddenSymbols.count == tokenCount)
            #expect(member.params.count == leadingCount + tokenCount)
            #expect(Array(member.params.dropFirst(leadingCount)).map(\.symbol) == hiddenSymbols)
            #expect(member.params.dropFirst(leadingCount).allSatisfy { $0.type == sema.types.intType })
            let stub = try findKIRFunction(named: name + "$default", in: module, interner: ctx.interner)
            #expect(stub.params.count == member.params.count + 1)
            #expect(Array(stub.params.dropFirst(leadingCount).dropLast()).map(\.symbol) == hiddenSymbols)
            let forwarded = try #require(stub.body.compactMap { instruction -> [KIRExprID]? in
                if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                   symbol == member.symbol { return arguments }
                return nil
            }.first)
            #expect(forwarded.count == member.params.count)
            #expect(forwarded.dropFirst(leadingCount).map { module.arena.expr($0) } == hiddenSymbols.map { .symbolRef($0) })
        }

        try LoweringPhase().run(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        for name in ["choice$default", "ordered$default", "extensionName$default", "direct", "defaults", "orderedProbe"] {
            let function = try findKIRFunction(named: name, in: module, interner: ctx.interner)
            let callees = extractCallees(from: function.body, interner: ctx.interner)
            #expect(!callees.contains("choice"))
            #expect(!callees.contains("ordered"))
            #expect(!callees.contains("extensionName"))
        }
    }
}
