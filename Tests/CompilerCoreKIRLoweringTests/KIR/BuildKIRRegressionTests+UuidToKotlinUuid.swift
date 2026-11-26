#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test func testToKotlinUuidLowersToRuntimeCallee() throws {
        let source = """
        @file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

        import java.util.UUID
        import kotlin.uuid.Uuid
        import kotlin.uuid.toKotlinUuid

        fun convert(javaUuid: UUID): Uuid = javaUuid.toKotlinUuid()
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "convert", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)

        #expect(
            callees.contains("toKotlinUuid"),
            "Expected toKotlinUuid call; found: \(callees)"
        )
    }

    @Test func testABILoweringMarksToKotlinUuidAsNonThrowing() {
        let pass = ABILoweringPass()
        let interner = StringInterner()
        let callees = pass.nonThrowingCallees(interner: interner)

        #expect(
            callees.contains(interner.intern(runtimeCallee(.uuidToKotlinUuid))),
            "The UUID interop bridge must not receive an outThrown slot during ABI lowering"
        )
    }
}
#endif
