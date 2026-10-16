@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testNullableStringPlusPrefersApplicableOperator(allowDefaultStdlibLibrary: Bool) throws {
        let sources = [
            """
            package stringplus.original
            operator fun String?.plus(p: String): String {
                return "" + this
            }
            fun test(a: String?, b: String): String {
                return a + b
            }
            fun box() = test("OK", " Fail")
            """,
            """
            package stringplus.minimal
            operator fun String?.plus(other: String): String = "CUSTOM"
            fun combine(left: String?, right: String): String = left + right
            fun box(): String = if (combine("O", "K") == "CUSTOM") "OK" else "FAIL"
            """,
            """
            package stringplus.control
            operator fun Int?.plus(other: String): String = "CUSTOM"
            fun combine(left: Int?, right: String): String = left + right
            fun box(): String = if (combine(1, "K") == "CUSTOM") "OK" else "FAIL"
            """,
            """
            package stringplus.concat
            fun box(): String = "O" + "K"
            """,
            """
            import stringplus.original.box as originalBox
            import stringplus.minimal.box as minimalBox
            import stringplus.control.box as controlBox
            import stringplus.concat.box as concatBox

            fun main() {
                println(originalBox())
                println(minimalBox())
                println(controlBox())
                println(concatBox())
            }
            """,
        ]

        for optLevel in [OptimizationLevel.O0, .O2] {
            try compileAndRunKotlinSources(
                sources,
                expectedOutput: "OK\nOK\nOK\nOK\n",
                moduleName: "NullableStringPlusOverride",
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
                optLevel: optLevel
            )
        }
    }
}
