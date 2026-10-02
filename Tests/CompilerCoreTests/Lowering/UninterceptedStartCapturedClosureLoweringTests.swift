#if canImport(Testing)
@testable import CompilerCore
import Testing

/// A suspend lambda that captures a mutable local reaches the unintercepted
/// entry-point intrinsics as `kk_function_create_N(adapter, closureState)`. The
/// adapter's suspend body reads the closure state from its first parameter, so the
/// rewrite must start it through the launcher thunk with the state stored in the
/// continuation's launcher-arg slot 0 (otherwise the entry reads garbage: SIGBUS).
@Suite
struct UninterceptedStartCapturedClosureLoweringTests {
    private func mainCallees(for source: String) throws -> [String] {
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let main = try findKIRFunction(named: "main", in: module, interner: ctx.interner)
        return extractCallees(from: main.body, interner: ctx.interner)
    }

    private func program(capturing: Bool, call: String) -> String {
        let body = capturing ? "starts++; 7" : "7"
        return """
        import kotlin.coroutines.*
        import kotlin.coroutines.intrinsics.*

        fun main() {
            var starts = 0
            val completion = Continuation<Int>(EmptyCoroutineContext) { r -> println(r.getOrThrow()) }
            val function: suspend () -> Int = { \(body) }
            println(function.\(call)(completion))
        }
        """
    }

    @Test
    func testCapturedVarThreadsClosureStateIntoLauncherArgSlot() throws {
        let callees = try mainCallees(for: program(capturing: true, call: "startCoroutineUninterceptedOrReturn"))
        #expect(callees.contains("kk_create_coroutine_unintercepted"))
        #expect(callees.contains("kk_start_coroutine_unintercepted_or_return"))
        #expect(callees.contains("kk_coroutine_launcher_arg_set"))
    }

    @Test
    func testCapturedVarThreadsClosureStateForStartCoroutine() throws {
        let callees = try mainCallees(for: program(capturing: true, call: "startCoroutine"))
        #expect(callees.contains("kk_coroutine_launcher_arg_set"))
    }

    @Test
    func testNonCapturingLambdaKeepsBareEntryPoint() throws {
        let callees = try mainCallees(for: program(capturing: false, call: "startCoroutineUninterceptedOrReturn"))
        #expect(callees.contains("kk_start_coroutine_unintercepted_or_return"))
        #expect(!callees.contains("kk_coroutine_launcher_arg_set"))
    }
}
#endif
