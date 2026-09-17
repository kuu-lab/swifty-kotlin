import Testing

// Kotlin's String.plus(other: Any?) renders a nullable String operand as the
// literal "null". Keep the flat-string lowering path honest for both binary
// `+` and compound assignment after the public operator moved to bundled
// Kotlin source (KSP-717 / KUU-523).
extension BundledStdlibExecutionTests {
    @Test
    func testNullableStringPlusAndCompoundAssignRenderNullLiteral() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                var local: String? = null
                local += 42
                println(local)

                val nullableLeft: String? = null
                println(nullableLeft + 42)

                val nullableRight: String? = null
                println("prefix" + nullableRight)
            }
            """,
            expectedOutput: "null42\nnull42\nprefixnull\n"
        )
    }
}
