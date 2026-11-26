import Testing

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
