#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - TypeCheckSemaPhase large-stack regression
//
// Regression coverage for a SIGBUS (signal 10) crash in `TypeCheckSemaPhase`:
// expression type inference (`ExprTypeChecker`/`CallTypeChecker`) recurses
// with a large per-frame `TypeInferenceContext` threaded by value through
// every call, and Swift Testing executes tests as tasks on the Swift
// Concurrency cooperative pool, whose worker threads have only 512 KiB
// stacks (vs. 8 MiB on the main thread). A chain of flow-sensitive
// collection member calls with trailing lambdas (`.map { }.filter { }...`)
// recurses through `CallTypeChecker.tryInferMemberCallCollectionFlowSpecials`
// / `tryBuiltinFlowMemberCall` / `ExprTypeChecker.inferLambdaLiteralExpr` for
// every link in the chain, and in a debug build even a handful of chained
// calls was enough to exhaust the 512 KiB stack and crash the whole test
// process with `___chkstk_darwin` / EXC_BAD_ACCESS before any test could
// report pass/fail.
//
// The fix runs `TypeCheckSemaPhase`'s type-checking pass on a dedicated
// large-stack thread via `LargeStackExecutor`, mirroring the existing fix
// for the analogous issue in `BuildKIRPhase` (KIR lowering).
@Suite
struct TypeCheckSemaPhaseLargeStackRegressionTests {

    @Test
    func testDeeplyChainedCollectionFlowCallsDoNotOverflowStack() throws {
        let source = """
            package repro

            fun deepChain(seq: Sequence<Int>): Sequence<Int> =
                seq
            \(chainedMapFilterCalls)

            fun main() {
                println(deepChain(sequenceOf(1, 2, 3)).toList())
            }

            """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])

            // Reaching this point at all (rather than crashing the process
            // with SIGBUS) is the regression signal.
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { "\($0.code): \($0.message)" })")
        }
    }

    /// 30 chained `.map { }.filter { }` links -- comfortably more than the
    /// handful of links that reproduced the original crash.
    private var chainedMapFilterCalls: String {
        Array(repeating: "        .map { it + 1 }.filter { it > 0 }", count: 30)
            .joined(separator: "\n")
    }
}

#endif
