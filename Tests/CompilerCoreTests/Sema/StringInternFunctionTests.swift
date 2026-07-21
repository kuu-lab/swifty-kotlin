#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-026: Validates that `String.intern()` resolves through Sema.
/// Runtime link name: `kk_string_intern`.
@Suite
struct StringInternFunctionTests {
    @Test func testInternFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun internString(s: String): String {
            return s.intern()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected intern to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
