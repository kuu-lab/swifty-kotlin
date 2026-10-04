@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test(arguments: [false, true])
    func testRunBlockingReceiverDoesNotOccupyLauncherCaptureSlot(capturesLocal: Bool) throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.*

        fun accept(scope: CoroutineScope) {}

        fun main() {
            val value = 42
            runBlocking {
                accept(this)
                println(\(capturesLocal ? "value" : "0"))
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let lambda = try #require(module.arena.declarations.compactMap { declaration -> KIRFunction? in
            guard case let .function(function) = declaration,
                  ctx.interner.resolve(function.name).hasPrefix("kk_lambda_"),
                  function.body.contains(where: { instruction in
                      guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                      return ctx.interner.resolve(callee) == "kk_coroutine_current_scope"
                  })
            else { return nil }
            return function
        }.first)
        #expect(lambda.params.count == (capturesLocal ? 1 : 0))
        let receiver = try #require(lambda.body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_coroutine_current_scope"
            else { return nil }
            return result
        }.first)
        #expect(lambda.body.contains { instruction in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else { return false }
            return ctx.interner.resolve(callee) == "accept" && arguments == [receiver]
        })
    }
}
