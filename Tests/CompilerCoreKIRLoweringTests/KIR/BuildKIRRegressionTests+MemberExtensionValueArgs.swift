#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BuildKIRRegressionTests {
    @Test func testMemberExtensionFunctionArgumentIsMaterializedPastBothReceivers() throws {
        let source = """
        class Box
        class Outer<R> {
            fun <E> Box.onThing(block: suspend (E) -> R) {}
            fun test(b: Box, r: R) {
                b.onThing<Int> { r }
            }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let module = try #require(ctx.kir)
        let testBody = try findKIRFunctionBody(named: "test", in: module, interner: ctx.interner)
        let callNames = extractCallees(from: testBody, interner: ctx.interner)
        #expect(callNames.contains(runtimeCallee(.functionCreate1)))

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
