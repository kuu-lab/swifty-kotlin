#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Source-backed `async(start = CoroutineStart.X)` must pass X to the async
/// bridge, whose Deferred handle carries the block's result.
@Suite
struct AsyncStartModeLoweringTests {
    /// Scan the whole module: the builder lives in the lowered runBlocking
    /// lambda, and its receiver requires the continuation-aware scope bridge.
    private func launcherStartModes(startMode: String) throws -> [Int64] {
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
            got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })
            """
        )

        let module = try #require(ctx.kir)
        return try LoweringTestRuntime.coroutineStartModes(
            for: "coroutine_scope_async_with_cont",
            legacyOperationPrefix: "kxmini_async", allowedLegacyOperations: ["kxmini_async_await"],
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
            "CoroutineStart.\(startMode) must reach exactly one async builder with start \(expected); got: \(modes)"
        )
    }

    /// The capture-bearing shape must preserve the mode on the same
    /// continuation-aware bridge as the receiver-only shape.
    @Test(arguments: [
        ("DEFAULT", Int64(0)),
        ("ATOMIC", Int64(2)),
        ("LAZY", Int64(1)),
        ("UNDISPATCHED", Int64(3)),
    ])
    func testCapturingBlockSelectsWithContVariant(startMode: String, expected: Int64) throws {
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
            got: \(ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" })
            """
        )

        let module = try #require(ctx.kir)
        let modes = try LoweringTestRuntime.coroutineStartModes(
            for: "coroutine_scope_async_with_cont",
            legacyOperationPrefix: "kxmini_async", allowedLegacyOperations: ["kxmini_async_await"],
            in: module, interner: ctx.interner
        )
        #expect(
            modes == [expected],
            "Capturing CoroutineStart.\(startMode) must preserve start \(expected); got: \(modes)"
        )
    }
}
#endif
