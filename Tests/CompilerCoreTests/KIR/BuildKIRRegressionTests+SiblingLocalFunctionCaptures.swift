#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test(arguments: [0, 1, 2])
    func testSiblingLocalFunctionForwardsCalleeCaptures(captureCount: Int) throws {
        let captures = ["a", "b"].prefix(captureCount).map { " + \($0)" }.joined()
        let ctx = makeContextFromSources([
            """
            fun outer(a: Double, b: Double): Double {
                fun within(x: Double, y: Double): Double = x + y\(captures)
                var x = 1.0
                var y = 2.0
                fun rxy(): Double = within(x, y)
                return rxy() + within(x, y)
            }
            """
        ])
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        let calleeSymbol = try sourceSymbol(named: "within", in: ctx)
        let callerSymbol = try sourceSymbol(named: "rxy", in: ctx)
        let callee = try #require(functions.first { $0.symbol == calleeSymbol })
        #expect(callee.params.count == 2 + captureCount)
        var callers: Set<SymbolID> = []
        for function in functions {
            for instruction in function.body {
                if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                   symbol == calleeSymbol
                {
                    #expect(arguments.count == callee.params.count)
                    callers.insert(function.symbol)
                }
            }
        }
        #expect(callers.contains(callerSymbol), "The sibling call must forward the callee's environment.")
        #expect(callers.count == 2, "Both direct and sibling calls must have complete capture arguments.")
    }
}
#endif
