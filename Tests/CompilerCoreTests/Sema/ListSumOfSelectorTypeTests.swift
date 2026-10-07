#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-1358: the `sumOf` selector overloads mirror upstream with only
/// Int/Long/Double/UInt/ULong selector return types. A selector returning any
/// other type (Float, String, Any, ...) has no viable overload and upstream
/// rejects the call; it used to silently arity-match the first (Int)
/// List.sumOf overload, which accumulated the boxed selector result as Int
/// bits and printed garbage.
@Suite
struct ListSumOfSelectorTypeTests {
    @Test
    func unsupportedSumOfSelectorsOnListProduceDiagnostics() throws {
        let source = """
        fun main() {
            println(listOf(1, 2).sumOf { it.toFloat() })
            println(mutableListOf(1, 2).sumOf { it.toFloat() })
            val values: List<Int> = listOf(1, 2)
            println(values.sumOf { it.toString() })
            val selector: (Int) -> Float = { it.toFloat() }
            println(values.sumOf(selector))
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0024"
        }
        #expect(
            diagnostics.count == 4,
            "Expected one unresolved sumOf diagnostic per unsupported selector, got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "sumOf", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 4, "Expected four user sumOf calls, got \(calls)")
        #expect(calls.allSatisfy { sema.bindings.callBinding(for: $0) == nil })
    }

    @Test
    func supportedSumOfSelectorsOnListKeepSourceBindings() throws {
        let source = """
        fun main() {
            println(listOf(1, 2, 3).sumOf { it })
            println(listOf(1, 2, 3).sumOf { it.toUInt() })
            println(listOf(1, 2, 3).sumOf { it.toDouble() })
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected supported sumOf selectors to resolve, got \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "sumOf", in: ast, interner: ctx.interner)
            .filter { isUserSourceExpr($0, in: ctx) }
        #expect(calls.count == 3, "Expected three user sumOf calls, got \(calls)")

        let expectedReturns: [TypeID] = [
            sema.types.intType,
            sema.types.uintType,
            sema.types.doubleType,
        ]
        for (callID, expectedReturn) in zip(calls, expectedReturns) {
            let binding = try #require(sema.bindings.callBinding(for: callID))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.returnType == expectedReturn)
        }
    }
}
#endif
