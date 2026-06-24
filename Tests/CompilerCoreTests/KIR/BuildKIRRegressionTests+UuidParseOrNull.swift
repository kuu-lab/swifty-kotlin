#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testUuidParseOrNullLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import kotlin.uuid.Uuid

        fun main() {
            val uuid = Uuid.parseOrNull("550e8400-e29b-41d4-a716-446655440000")
            uuid?.toString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_uuid_parseOrNull"),
                "Expected Uuid.parseOrNull runtime call"
            )
        }
    }

    @Test func testABILoweringMarksUuidParseOrNullAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(
            callees.contains(interner.intern("kk_uuid_parseOrNull")),
            "kk_uuid_parseOrNull should not receive an outThrown slot during ABI lowering"
        )
    }
}
#endif
