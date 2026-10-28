@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NullableLocalIncrementAssignmentTypeTests {
    @Test
    func nullablePrimitiveIncExtensionCanCallPrimitiveIncAfterNullCheck() throws {
        let ctx = makeContextFromSource("""
        operator fun Int?.inc(): Int {
            if (this != null) return this.inc()
            throw NullPointerException()
        }
        fun incrementNullable() {
            var value: Int? = 10
            value++
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nullableIncAndDecResultsFitDeclaredNullableLocalType() throws {
        let ctx = makeContextFromSource("""
        class C
        operator fun C?.inc(): C? = null
        operator fun C?.dec(): C? = null
        fun validInc() {
            var value: C?
            value = C()
            ++value
        }
        fun validDec() {
            var value: C?
            value = C()
            --value
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nullableIncAndDecResultsDoNotFitDeclaredNonNullableLocalType() throws {
        let ctx = makeContextFromSource("""
        class C
        operator fun C?.inc(): C? = null
        operator fun C?.dec(): C? = null
        fun invalidInc() {
            var value: C = C()
            ++value
        }
        fun invalidDec() {
            var value: C = C()
            --value
        }
        """)
        try runSema(ctx)

        let incrementAssignmentErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0303"
        }
        #expect(incrementAssignmentErrors.count == 2, "\(ctx.diagnostics.diagnostics)")
    }
}
