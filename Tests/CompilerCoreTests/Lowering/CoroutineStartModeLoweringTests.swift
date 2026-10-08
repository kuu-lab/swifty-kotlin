#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Source-backed `launch(start = CoroutineStart.X)` must pass X to the launch
/// bridge, preserving eager, lazy, atomic and undispatched start modes.
///
/// Lowering used to route *any* `CoroutineStart`-typed first argument to the
/// lazy launcher and never read the value, so `DEFAULT`, `ATOMIC` and
/// `UNDISPATCHED` all compiled to a body that did not start until something
/// joined it.
@Suite
struct CoroutineStartModeLoweringTests {
    /// Scan the whole module: the builder lives in the lowered runBlocking
    /// lambda, and its receiver requires the continuation-aware scope bridge.
    private func launcherStartModes(startMode: String) throws -> [Int64] {
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
        return try LoweringTestRuntime.coroutineStartModes(
            for: "coroutine_scope_launch_context_with_cont", legacyOperationPrefix: "kxmini_launch",
            in: module, interner: ctx.interner
        )
    }

    @Test(arguments: [
        ("DEFAULT", Int64(0)),
        ("ATOMIC", Int64(2)),
        ("LAZY", Int64(1)),
        ("UNDISPATCHED", Int64(3)),
    ])
    func testStartModeSelectsItsRuntimeLauncher(startMode: String, expected: Int64) throws {
        let modes = try launcherStartModes(startMode: startMode)
        #expect(
            modes == [expected],
            "CoroutineStart.\(startMode) must reach exactly one launch builder with start \(expected); got: \(modes)"
        )
    }
}
#endif
