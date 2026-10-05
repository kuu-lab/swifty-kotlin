@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test(arguments: [0, 1, 4])
    func testStoredSuspendReceiverValueBoxesCaptureEnvironment(parameterCount: Int) throws {
        let parameters = Array(repeating: "Int", count: parameterCount).joined(separator: ", ")
        let names = (0..<parameterCount).map { "p\($0)" }.joined(separator: ", ")
        let ctx = makeContextFromSource("""
        fun main() {
            val label = "v"
            val body: suspend String.(\(parameters)) -> Unit = {
                \(parameterCount == 0 ? "" : names + " ->")
                println("$label:$this")
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let functions = module.arena.declarations.compactMap { declaration -> KIRFunction? in
            guard case let .function(function) = declaration else { return nil }
            return function
        }
        let main = try #require(functions.first { ctx.interner.resolve($0.name) == "main" })
        #expect(extractCallees(from: main.body, interner: ctx.interner).contains("kk_function_create_\(parameterCount + 1)"))
        let adapter = try #require(functions.first {
            ctx.interner.resolve($0.name).hasPrefix("kk_function_value_adapter_")
        })
        #expect(adapter.isSuspend)
        #expect(adapter.params.count == parameterCount + 2)
        let captureLoad = try #require(adapter.body.compactMap { instruction -> KIRExprID? in
            guard case let .call(_, callee, args, result, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee) == "kk_array_get_inbounds",
                  case .intLiteral(2) = module.arena.expr(args[1])
            else { return nil }
            return result
        }.first)
        let lambdaArgs = try #require(adapter.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(_, callee, args, _, _, _, _, _) = instruction,
                  ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
            else { return nil }
            return args
        }.first)
        #expect(lambdaArgs.count == parameterCount + 2)
        #expect(lambdaArgs[0] == captureLoad)
        #expect(module.arena.expr(lambdaArgs[1]) == .symbolRef(adapter.params[1].symbol))
    }

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
