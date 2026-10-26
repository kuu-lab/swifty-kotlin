#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendNonNullableCallNullComparisonTests {
    @Test
    func testUncheckedCastNullComparedToNullUsesRuntimeValue() throws {
        let source = """
        @Suppress("UNCHECKED_CAST")
        fun <T> uncheckedCastNull(): T = null as T

        fun main() {
            val s: String = uncheckedCastNull()
            val i: Int = uncheckedCastNull()
            val longMin: Long = Long.MIN_VALUE
            val negativeZero: Double = -0.0
            println(s)
            println(s == null)
            println(s != null)
            println(uncheckedCastNull<Int>() == null)
            println(i == null)
            println(i != null)
            val nullable: Int? = uncheckedCastNull()
            println(nullable == null)
            println("present" == null)
            println(longMin == null)
            println(longMin != null)
            println(negativeZero == null)
            println(negativeZero != null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "UncheckedCastNullComparison",
            expected: "null\ntrue\nfalse\ntrue\ntrue\nfalse\ntrue\nfalse\nfalse\ntrue\nfalse\ntrue\n"
        )
    }

    @Test
    func testNonNullablePrimitiveCallComparedToNullPreservesSideEffects() throws {
        let source = """
        var result = "fail"
        fun withSideEffect(): Int {
            result = "OK"
            return 42
        }

        fun main() {
            if (withSideEffect() == null) { }
            println(result)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "NonNullableCallNullComparisonSideEffects",
            expected: "OK\n"
        )
    }
}
#endif
