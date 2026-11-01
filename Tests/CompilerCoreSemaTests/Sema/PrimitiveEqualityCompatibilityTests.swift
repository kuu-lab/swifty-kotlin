@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrimitiveEqualityCompatibilityTests {
    @Test
    func rejectsEqualityBetweenDifferentNumericPrimitiveTypes() throws {
        let source = """
        fun doubleInt() = 0.6 != 1
        fun intDouble() = 1 != 0.6
        fun floatLong() = 1.0f == 1L
        fun sameType() = 0.6 == 0.6
        fun orderedComparison() = 0.6 < 1
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 3, "Expected errors only for mixed-type equality: \(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0471" })
        #expect(errors.allSatisfy { $0.message.contains("cannot be applied to unrelated types") })
    }
}
