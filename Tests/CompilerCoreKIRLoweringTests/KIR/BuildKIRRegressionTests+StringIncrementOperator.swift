#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test func testBuildKIRUsesStringIncExtensionForPrefixIncrement() throws {
        let ctx = makeContextFromSource("""
        operator fun String.inc(): String = "INC"
        fun useOperator(): String {
            var value = "ab"
            return ++value
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let incrementExprID = try #require(ast.arena.exprs.indices.first(where: { index in
            ast.arena.isIncrementDecrement(ExprID(rawValue: Int32(index)))
        }).map { ExprID(rawValue: Int32($0)) })
        let binding = try #require(sema.bindings.callBindings[incrementExprID])
        let chosenSymbol = binding.chosenCallee
        #expect(sema.symbols.symbol(chosenSymbol)?.name == ctx.interner.intern("inc"))

        try BuildKIRPhase().run(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "useOperator", in: module, interner: ctx.interner)
        #expect(body.contains { instruction in
            guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
            return symbol == chosenSymbol
        })
        #expect(!extractCallees(from: body, interner: ctx.interner).contains(runtimeCallee(.stringConcatFlat)))
    }
}
#endif
