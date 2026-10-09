#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BuildKIRRegressionTests {
    /// KUU-962: member-extension calls carry TWO leading receiver slots in the
    /// lowered arguments -- [dispatch, extension, ...valueArgs] -- while the
    /// callee signature only counts the extension receiver. Materializing
    /// function-typed value arguments must start past both slots; otherwise
    /// parameter 0 maps onto the extension receiver and a `suspend (E) -> R`
    /// block is passed as a bare `symbolRef`, whose aggregate-parameter thunk
    /// ABI the callee's kk_suspend_function_invoke cannot drive.
    @Test func testMemberExtensionFunctionArgumentIsMaterializedPastBothReceivers() throws {
        let source = """
        class Box
        class Outer<R> {
            fun <E> Box.onThing(block: suspend (E) -> R) {}
            fun test(b: Box) {
                b.onThing<Int> { it + 1 }
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let testBody = try findKIRFunctionBody(named: "test", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: testBody, interner: ctx.interner)
        #expect(callNames.contains(runtimeCallee(.functionCreate1)))

        // The materialized function value (the kk_function_create_1 result)
        // must be the argument handed to the member-extension callee -- not a
        // raw `symbolRef` of the lambda thunk.
        var createResult: KIRExprID?
        var memberCallArguments: [KIRExprID]?
        for instruction in testBody {
            switch instruction {
            case let .call(_, callee, _, result, _, _, _, _)
                where callee == ctx.interner.intern(runtimeCallee(.functionCreate1)):
                createResult = result
            case let .call(_, callee, arguments, _, _, _, _, _)
                where callee == ctx.interner.intern("onThing"):
                memberCallArguments = arguments
            case let .virtualCall(_, callee, _, arguments, _, _, _, _)
                where callee == ctx.interner.intern("onThing"):
                memberCallArguments = arguments
            default:
                continue
            }
        }
        let materialized = try #require(createResult, "expected kk_function_create_1 wrapping the suspend block")
        let callArgs = try #require(memberCallArguments, "expected an onThing call in test")
        #expect(callArgs.count == 3, "member-extension call args must be [dispatch, extension, block]")
        #expect(callArgs.last == materialized, "block argument must be the materialized function value")
    }
}
#endif
