@testable import CompilerCore
import Testing

/// KSP-1364: Validates the no-argument CharSequence.any() overload through Sema.
@Suite
struct CharSequenceAnyNoArgFunctionTests {
    @Test func testAnyNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun anyOnString(): Boolean = "x".any()
        fun anyOnEmptyString(): Boolean = "".any()
        fun anyOnCharSequence(cs: CharSequence): Boolean = cs.any()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected CharSequence.any() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
