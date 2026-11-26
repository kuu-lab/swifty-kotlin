#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testPrintlnCharArrayPrintsContents() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val r = CharArray(10) { 'x' }
                r[3] = '#'
                println(r)
                print(r)
                println()
                println(charArrayOf('a', 'b', 'c'))
                println(CharArray(0) { 'x' })
            }
            """,
            expectedOutput: "xxx#xxxxxx\nxxx#xxxxxx\nabc\n\n",
            moduleName: "PrintlnCharArray"
        )
    }
}
#endif
