#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testToKotlinUuidLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import java.util.UUID
        import kotlin.uuid.Uuid
        import kotlin.uuid.toKotlinUuid

        fun convert(javaUuid: UUID): Uuid = javaUuid.toKotlinUuid()
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            // KSP-476: toKotlinUuid() is now a regular Kotlin function whose body
            // calls the private __kk_uuid_toKotlinUuid bridge. At this frontend-only
            // stage the bridge call isn't visible from `convert`'s own KIR body (the
            // wrapper's body isn't lowered into this module) — only the call-site's
            // simple callee name is. Full bridge verification lives in
            // RuntimeUuidToKotlinUuidTests and diff_kotlinc.
            let body = try findKIRFunctionBody(named: "convert", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("toKotlinUuid"),
                "Expected toKotlinUuid call; found: \(callees)"
            )
        }
    }

    @Test func testABILoweringMarksToKotlinUuidAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(
            callees.contains(interner.intern("__kk_uuid_toKotlinUuid")),
            "__kk_uuid_toKotlinUuid should not receive an outThrown slot during ABI lowering"
        )
    }
}
#endif
