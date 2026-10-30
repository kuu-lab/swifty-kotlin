#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test
    func labeledRepeatReturnInsideRunInSuspendLambdaHasInlineExternalJump() throws {
        let source = """
        package kotlin

        inline fun run(block: () -> Unit) { block() }
        inline fun repeat(times: Int, action: (Int) -> Unit) {
            var index = 0
            while (index < times) {
                action(index)
                index++
            }
        }
        suspend fun use(block: suspend () -> Unit) { block() }

        suspend fun whatever() {
            use {
                repeat(10) {
                    run {
                        return@repeat
                    }
                }
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let functions = module.arena.declarations.compactMap(\.function)
            let externalLoopJumpFunctions = functions.filter { function in
                function.body.contains { instruction in
                    guard case let .jump(target) = instruction else { return false }
                    return KIRExternalLoopJump.label(for: target) != nil
                }
            }
            #expect(!externalLoopJumpFunctions.isEmpty)
            #expect(externalLoopJumpFunctions.allSatisfy { $0.isInlineOnly })

            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
