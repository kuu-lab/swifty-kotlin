#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// `async(start = CoroutineStart.X)` must select the runtime launcher that
/// actually implements X.
///
/// The overload did not exist: only a single-argument `async(block:)` was
/// registered, so the call failed to type-check (KSWIFTK-SEMA-0002), and the
/// two-argument start-mode rewrite was gated on the callee being `launch`.
///
/// The launch-side counterpart lives in `CoroutineStartModeLoweringTests`.
/// `async` needs its own launcher family rather than sharing launch's: its
/// handles are `Deferred`s carrying the block's result, where launch's are
/// `Job`s.
@Suite
struct AsyncStartModeLoweringTests {
    /// Every `kk_kxmini_async*` callee the lowered module reaches for an
    /// `async(start = CoroutineStart.<startMode>)` call.
    ///
    /// The whole module is scanned rather than just `main`: the async call is
    /// rewritten inside the lambda-derived suspend function the compiler
    /// synthesises for the `runBlocking` body, not in `main` itself. These
    /// names are unique to the async lowering, so nothing in the bundled stdlib
    /// compiled alongside the input can contribute a false hit.
    ///
    /// `kk_kxmini_async_await` is filtered out: it is emitted by `await()`
    /// rather than chosen by the start mode, so it appears for every mode.
    private func launcherCallees(startMode: String) throws -> Set<String> {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val deferred = async(start = CoroutineStart.\(startMode)) {
                println("body")
                7
            }
            println(deferred.await())
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            """
            Expected no errors for CoroutineStart.\(startMode), \
            got: \(ctx.diagnostics.diagnostics.map(\.code))
            """
        )

        let module = try #require(ctx.kir)
        var callees: Set<String> = []
        for function in findAllKIRFunctions(in: module) {
            for callee in extractCallees(from: function.body, interner: ctx.interner)
                where callee.hasPrefix("kk_kxmini_async") && callee != "kk_kxmini_async_await"
            {
                callees.insert(callee)
            }
        }
        return callees
    }

    /// The three launchers a start mode can select. `DEFAULT` and `ATOMIC`
    /// share one: they differ only in whether a cancellation arriving before
    /// the first suspension can still stop the body, which this runtime does
    /// not model separately.
    private static let allLaunchers: Set<String> = [
        "kk_kxmini_async",
        "kk_kxmini_async_lazy",
        "kk_kxmini_async_undispatched",
    ]

    @Test(arguments: [
        ("DEFAULT", "kk_kxmini_async"),
        ("ATOMIC", "kk_kxmini_async"),
        ("LAZY", "kk_kxmini_async_lazy"),
        ("UNDISPATCHED", "kk_kxmini_async_undispatched"),
    ])
    func testStartModeSelectsItsRuntimeLauncher(startMode: String, expected: String) throws {
        let callees = try launcherCallees(startMode: startMode)

        #expect(
            callees.contains(expected),
            "CoroutineStart.\(startMode) should lower to \(expected), got: \(callees.sorted())"
        )

        let wrong = callees.intersection(Self.allLaunchers.subtracting([expected]))
        #expect(
            wrong.isEmpty,
            "CoroutineStart.\(startMode) also selected \(wrong.sorted())"
        )
    }

    /// The capture-bearing shape routes through the launcher thunk, which needs
    /// the `_with_cont` sibling of each start mode's entry point. A block that
    /// closes over an outer variable used to be the only way to reach these.
    @Test(arguments: [
        ("DEFAULT", "kk_kxmini_async_with_cont"),
        ("ATOMIC", "kk_kxmini_async_with_cont"),
        ("LAZY", "kk_kxmini_async_lazy_with_cont"),
        ("UNDISPATCHED", "kk_kxmini_async_undispatched_with_cont"),
    ])
    func testCapturingBlockSelectsWithContVariant(startMode: String, expected: String) throws {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val captured = 7
            val deferred = async(start = CoroutineStart.\(startMode)) {
                println(captured)
                captured
            }
            println(deferred.await())
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            """
            Expected no errors for capturing CoroutineStart.\(startMode), \
            got: \(ctx.diagnostics.diagnostics.map(\.code))
            """
        )

        let module = try #require(ctx.kir)
        var callees: Set<String> = []
        for function in findAllKIRFunctions(in: module) {
            for callee in extractCallees(from: function.body, interner: ctx.interner)
                where callee.hasPrefix("kk_kxmini_async") && callee != "kk_kxmini_async_await"
            {
                callees.insert(callee)
            }
        }

        #expect(
            callees.contains(expected),
            """
            Capturing CoroutineStart.\(startMode) should lower to \(expected), \
            got: \(callees.sorted())
            """
        )
    }
}
#endif
