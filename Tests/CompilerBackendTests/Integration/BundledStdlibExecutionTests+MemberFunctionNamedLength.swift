import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testMemberFunctionNamedLengthUsesItsInferredReturnValue() throws {
        try compileAndRunKotlin(
            """
            class NameBox(val name: String?) {
                fun length() = name?.let { it.length }
            }

            fun main() {
                println(NameBox("x").length())
                println(NameBox(null).length())
            }
            """,
            expectedOutput: "1\nnull\n",
            moduleName: "MemberFunctionNamedLength"
        )
    }
}
