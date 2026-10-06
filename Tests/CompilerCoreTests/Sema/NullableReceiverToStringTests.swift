#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Regression coverage for KUU-751: Kotlin's `Any?.toString()` extension must
/// be callable from nullable receivers, including a null literal.
@Suite
struct NullableReceiverToStringTests {
    @Test
    func nullableStringAndNullLiteralResolveToString() {
        let source = """
        fun main() {
            val s: String? = null
            println(s.toString())
            val s2: String? = "x"
            println(s2.toString())
            println(null.toString())
        }
        """
        let ctx = makeContextFromSource(source)
        do {
            try runToKIR(ctx)
        } catch {
            // The diagnostics below are the assertion for this regression.
        }

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Nullable String and null-literal toString() should resolve, got: \(errors)"
        )
    }
}
#endif
