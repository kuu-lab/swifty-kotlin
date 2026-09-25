#if canImport(Testing)
@testable import CompilerCore
import Foundation
#if canImport(Dispatch)
import Dispatch
#endif
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
//
// The bundled stdlib itself hits the same recursion through its own flow /
// collection HOF bodies (`flow { source.collect { transform(v).collect {
// emit } } }` nests `tryBuiltinFlowMemberCall` -> `inferLambdaLiteralExpr`
// cycles): a one-line input compiled with bundled-source stdlib injection
// was enough to exhaust a 512 KiB thread and record "Thread stack size
// exceeded" in the host crash log (BUG-213).
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

    @Test
    func testBundledStdlibSemaDoesNotOverflowThinCallerStack() throws {
        // BUG-213 repro: the stack-heavy work lives entirely inside the
        // bundled stdlib's own flow/collection bodies, so the user input is
        // a one-line file compiled with bundled-source stdlib injection
        // (`makeCompilationContext` defaults `allowDefaultStdlibLibrary:
        // false`, i.e. source injection rather than the .kklib artifact).
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])

            // `swiftpm-testing-helper` runs tests on Swift Concurrency
            // cooperative-pool threads with 512 KiB stacks. Invoke `runSema`
            // from an identically sized thread so the check does not depend
            // on which pool thread the harness happens to pick -- without
            // `TypeCheckSemaPhase`'s `LargeStackExecutor` hop this overflows
            // the caller's stack and kills the test process (SIGSEGV).
            try runOnThread(stackSize: 512 << 10) {
                try runSema(ctx)
            }

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { "\($0.code): \($0.message)" })")
        }
    }

    /// Runs `body` synchronously on a dedicated `Thread` with `stackSize`
    /// bytes of stack, then rethrows its result. The semaphore join makes
    /// the hand-off back to the caller thread safe.
    private func runOnThread(stackSize: Int, _ body: @escaping () throws -> Void) throws {
        let box = ThinStackWorkBox(body)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.run()
            done.signal()
        }
        thread.stackSize = stackSize
        thread.start()
        done.wait()
        try box.result!.get()
    }

    /// Carries the closure and its `Result` across the thread boundary.
    /// `@unchecked Sendable` because the join back to the caller thread
    /// provides the synchronization that makes the hand-off safe.
    private final class ThinStackWorkBox: @unchecked Sendable {
        let body: () throws -> Void
        var result: Result<Void, any Error>?

        init(_ body: @escaping () throws -> Void) {
            self.body = body
        }

        func run() {
            result = Result(catching: body)
        }
    }
}

#endif
