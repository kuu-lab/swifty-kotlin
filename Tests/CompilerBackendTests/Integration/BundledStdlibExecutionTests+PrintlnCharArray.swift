#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    // KUU-2754 regression: println(CharArray)/print(CharArray) must resolve to
    // the CharArray overload that prints the characters, not the Any? overload
    // whose toString renders kotlin.CharArray@hash.
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
