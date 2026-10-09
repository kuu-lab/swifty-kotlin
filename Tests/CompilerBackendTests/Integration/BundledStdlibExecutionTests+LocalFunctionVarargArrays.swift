import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testLocalFunctionVarargArrays() throws {
        try compileAndRunKotlin(
            """
            class T {
                fun f() {
                    fun va(vararg a: String): Array<out String> = a
                    println(va("x", "y").size)
                }
            }
            fun main() {
                T().f()
                fun va(vararg a: String): Array<out String> = a
                println(va("x", "y").size)
            }
            """,
            expectedOutput: "2\n2\n",
            moduleName: "KUU1684LocalFunctionVarargArrays"
        )
    }
}
