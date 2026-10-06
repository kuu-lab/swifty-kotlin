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
    @Test
    func testStandaloneStartMarkersIncludeUnusedContextSlot() throws {
        let ctx = makeContextFromSource("fun main() { println(\"hello\") }", emit: .object)
        try runToLowering(ctx)
        let module = try #require(ctx.kir)
        let expectedArities = [
            "kk_start_coroutine_unintercepted_or_return_no_receiver": 3,
            "kk_start_coroutine_unintercepted_or_return_with_receiver": 4,
        ]
        var seen = Set<String>()
        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration else { continue }
            for instruction in function.body {
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      let expectedArity = expectedArities[ctx.interner.resolve(callee)] else { continue }
                seen.insert(ctx.interner.resolve(callee))
                #expect(arguments.count == expectedArity)
            }
        }
        #expect(seen == Set(expectedArities.keys))
    }

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
    func testCapturedStartCoroutinePreservesBoxedCallableForSourceBuilder() throws {
        let callees = try mainCallees(for: program(capturing: true, call: "startCoroutine"))
        // The non-inline source builder receives the boxed callable; the
        // runtime create bridge transfers its closure state into the launcher.
        #expect(callees.contains("startCoroutine"))
        #expect(callees.contains("kk_suspend_function_create"))
    }

    @Test
    func testNonCapturingLambdaKeepsBareEntryPoint() throws {
        let callees = try mainCallees(for: program(capturing: false, call: "startCoroutineUninterceptedOrReturn"))
        #expect(callees.contains("kk_start_coroutine_unintercepted_or_return"))
        #expect(!callees.contains("kk_coroutine_launcher_arg_set"))
    }
}
#endif
