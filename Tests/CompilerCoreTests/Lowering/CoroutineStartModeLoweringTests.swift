#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// `launch(start = CoroutineStart.X)` must select the runtime launcher
/// that actually implements X.
///
/// Lowering used to route *any* `CoroutineStart`-typed first argument to the
/// lazy launcher and never read the value, so `DEFAULT`, `ATOMIC` and
/// `UNDISPATCHED` all compiled to a body that did not start until something
/// joined it.
@Suite
struct CoroutineStartModeLoweringTests {
    /// Every `kk_kxmini_launch*` callee the lowered module reaches for a
    /// `launch(start = CoroutineStart.<startMode>)` call.
    ///
    /// The whole module is scanned rather than just `main`: the launch is
    /// rewritten inside the lambda-derived suspend function the compiler
    /// synthesises for the `runBlocking` body, not in `main` itself. These
    /// names are unique to the launch lowering, so nothing in the bundled
    /// stdlib compiled alongside the input can contribute a false hit.
    private func launcherCallees(startMode: String) throws -> Set<String> {
        let source = """
        import kotlinx.coroutines.*

        fun main() = runBlocking {
            val job = launch(start = CoroutineStart.\(startMode)) {
                println("body")
            }
            job.join()
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
                where callee.hasPrefix("kk_kxmini_launch")
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
        "kk_kxmini_launch",
        "kk_kxmini_launch_lazy",
        "kk_kxmini_launch_undispatched",
    ]

    @Test(arguments: [
        ("DEFAULT", "kk_kxmini_launch"),
        ("ATOMIC", "kk_kxmini_launch"),
        ("LAZY", "kk_kxmini_launch_lazy"),
        ("UNDISPATCHED", "kk_kxmini_launch_undispatched"),
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
}
#endif
