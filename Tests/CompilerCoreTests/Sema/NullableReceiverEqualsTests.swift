#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Regression coverage for KUU-3477: `equals` requires a safe call on nullable receivers.
@Suite
struct NullableReceiverEqualsTests {
    @Test
    func rejectsBareEqualsOnNullableAny() throws {
        let ctx = makeContextFromSource("""
        fun inspect(value: Any?) {
            value.equals(null)
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Expected one nullable-receiver error, got: \(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0026", "Unexpected diagnostics: \(errors)")
    }

    @Test
    func preservesSafeEqualsAndOtherNullableAnyOperations() throws {
        let ctx = makeContextFromSource("""
        fun inspect(nullable: Any?, nonNull: Any) {
            val safeEquals: Boolean? = nullable?.equals(nonNull)
            val safeHashCode: Int? = nullable?.hashCode()
            val nonNullEquals: Boolean = nonNull.equals(nonNull)
            val equalsNull: Boolean = nullable == null
            if (nullable != null) {
                val smartCastEquals: Boolean = nullable.equals(nonNull)
            }
            nullable.toString()
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Expected legal nullable operations to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
