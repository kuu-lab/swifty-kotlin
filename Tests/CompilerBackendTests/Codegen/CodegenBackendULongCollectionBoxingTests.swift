#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendULongCollectionBoxingTests {
    @Test(arguments: [false, true], [0, 2])
    func testParsedULongAnyCallbackReturns(useArtifact: Bool, optimizationLevel: Int) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimizationLevel))
        let source = try diffCaseSource("string_ulong_any_callback.kt", file: #filePath)
        // Kotlin/JVM 2.3.10 output: every present erased value remains a ULong.
        let high = "9223372036854775808:true\n"
        let max = "18446744073709551615:true\n"
        let expected = [high, max, high, max].map {
            "true\n" + String(repeating: $0, count: 7)
        }.joined() + high + max + high + max + """
        null:false
        null:false
        NFE:Invalid number format: '18446744073709551616'
        IAE:radix 1 was not in valid range 2..36
        """ + "\n"
        try assertKotlinOutput(
            source,
            moduleName: "ParsedULongAnyCallbackReturns",
            expected: expected,
            optLevel: optLevel,
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    /// Regression: runtimeNullSentinelInt is Int64.min, which is also the raw
    /// bit pattern of ULong(2^63) and Long.MIN_VALUE. kk_box_ulong / kk_box_long
    /// used to short-circuit on that bit pattern and return it unboxed, so this
    /// one ordinary value got silently treated as null by every boxed-Any
    /// dispatch site (toString, equality, `is`). Verifies both the non-nullable
    /// boxing path and null still propagating correctly through nullable ULong?/
    /// Long? — including as a generic Any? function argument, which is a
    /// different lowering path than a plain `val x: Any? = ...` assignment.
    @Test
    func testULongAndLongBoxingAtNullSentinelBoundary() throws {
        let source = """
        fun show(x: Any?) {
            println(x)
        }

        fun main() {
            val big: ULong = 9223372036854775808uL
            val any: Any = big
            println(any)

            val nullU: ULong? = null
            val anyNull: Any? = nullU
            println(anyNull)
            show(nullU)

            val presentU: ULong? = 9223372036854775808uL
            val anyPresent: Any? = presentU
            println(anyPresent)
            show(presentU)

            val bigL: Long = Long.MIN_VALUE
            val anyL: Any = bigL
            println(anyL)

            val nullL: Long? = null
            show(nullL)

            val presentL: Long? = Long.MIN_VALUE
            show(presentL)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "ULongLongNullSentinelBoundary",
            expected:
                """
                9223372036854775808
                null
                null
                9223372036854775808
                9223372036854775808
                -9223372036854775808
                null
                -9223372036854775808
                """
                + "\n"
        )
    }
}
#endif
