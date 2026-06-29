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
            let body = try findKIRFunctionBody(named: "convert", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_uuid_toKotlinUuid"),
                "Expected kk_uuid_toKotlinUuid runtime call; found: \(callees.sorted())"
            )
        }
    }

    @Test func testABILoweringMarksToKotlinUuidAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(
            callees.contains(interner.intern("kk_uuid_toKotlinUuid")),
            "kk_uuid_toKotlinUuid should not receive an outThrown slot during ABI lowering"
        )
    }
}
#endif
