#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    @Test
    func systemErrPrintlnSeparatesStandardErrorFromStandardOutput() throws {
        try compileAndRunKotlin(
            """
            fun main(){System.err.println("error");println("ok")}
            """,
            expectedOutput: "ok\n",
            expectedErrorOutput: "error\n"
        )
    }

    @Test
    func systemErrPrintsStringsNumbersAndNullWithNewlineOverloads() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                System.err.print("prefix=")
                System.err.println(42)
                System.err.println(null)
                System.err.println()
                println("stdout")
            }
            """,
            expectedOutput: "stdout\n",
            expectedErrorOutput: "prefix=42\nnull\n\n"
        )
    }
}
#endif
