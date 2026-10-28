#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct WhenSubjectConditionTypeCompatibilityTests {
    @Test func rejectsDoubleLiteralForIntWhenSubject() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val x = 1
            when (x) {
                1.0 -> println("double")
                else -> println("else")
            }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Got: \(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0002")
        #expect(errors.first?.message.contains("unrelated types") == true)
    }

    @Test func rejectsConditionsIncompatibleWithTheSubjectType() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            when (1) {
                1 -> println(1)
                true -> println(2)
            }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "Got: \(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0002")
        #expect(errors.first?.message.contains("unrelated types") == true)
    }

    @Test func preservesValidBooleanTypeAndMembershipConditions() throws {
        let ctx = makeContextFromSource("""
        fun boolean(flag: Boolean): Int = when (flag) {
            true -> 1
            false -> 0
        }
        fun membership(value: Int): Int = when (value) {
            in 1..3 -> 1
            else -> 0
        }
        fun typeCheck(value: Any): Int = when (value) {
            is Int -> 1
            else -> 0
        }
        fun nullable(value: Int?): Int = when (value) {
            null -> 0
            1 -> 1
            else -> 2
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
