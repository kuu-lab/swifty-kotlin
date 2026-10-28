#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test
    func testRecursiveLocalFunctionForwardsCaptureThroughLambda() throws {
        let ctx = makeContextFromSources([
            """
            fun apply(n: Int, action: (Int) -> Int): Int = action(n)
            fun outer(): Int {
                var total = 0
                val limit = 10
                fun countdown(n: Int): Int {
                    total += 1
                    if (n <= 0) return limit + total
                    return apply(n - 1) { countdown(it) }
                }
                return countdown(5)
            }
            """
        ])
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        let symbol = try sourceSymbol(named: "countdown", in: ctx)
        let countdown = try #require(functions.first { $0.symbol == symbol })
        #expect(countdown.params.count == 3)
        var callers: Set<SymbolID> = []
        for function in functions {
            for instruction in function.body {
                if case let .call(callee, _, arguments, _, _, _, _, _) = instruction,
                   callee == symbol
                {
                    #expect(arguments.count == countdown.params.count)
                    callers.insert(function.symbol)
                }
            }
        }
        #expect(callers.count == 2, "Both the outer function and nested lambda must forward captures.")
    }
}
#endif
