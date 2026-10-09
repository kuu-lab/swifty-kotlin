#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func inlineMemberArgumentsPreserveNonLocalAndLabeledReturns() throws {
        let context = makeContextFromSource("""
        class Receiver {
            inline fun call(crossinline other: () -> Int, action: () -> Int): Int = action()
        }
        fun direct(receiver: Receiver): Int {
            receiver.call({ 0 }) { return 11 }
            return -1
        }
        fun safe(receiver: Receiver?): Int {
            receiver?.call(action = { return 12 }, other = { 0 })
            return -1
        }
        fun labeled(receiver: Receiver): Int {
            receiver.call({ 0 }) { return@call 13 }
            return 14
        }
        fun captured(receiver: Receiver, value: Int): Int {
            receiver.call({ 0 }) { return value }
            return -1
        }
        """)
        try runToKIR(context)
        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors.map(\.message))")
        let module = try #require(context.kir)
        let lambdas = try findKIRLambdaFunctions(in: context)
        let nonLocalLambdas = lambdas.filter { function in
            function.body.contains { instruction in
                if case .nonLocalReturn = instruction { return true }
                return false
            }
        }
        #expect(nonLocalLambdas.count == 3)
        #expect(nonLocalLambdas.allSatisfy { $0.isInlineOnly })
        #expect(lambdas.count == 8)
        #expect(lambdas.filter { !$0.isInlineOnly }.count == 5)
        let nonLocalSymbols = Set(nonLocalLambdas.map(\.symbol))
        // Crossinline arguments may need adapters, but non-local returns
        // must remain in their inline-only lambdas.
        let lambdaSymbols = Set(lambdas.map(\.symbol))
        #expect(!findAllKIRFunctions(in: module).contains { function in
            guard !lambdaSymbols.contains(function.symbol) else { return false }
            return function.body.contains { instruction in
                guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction else { return false }
                return nonLocalSymbols.contains(symbol)
            }
        })
    }
}
#endif
