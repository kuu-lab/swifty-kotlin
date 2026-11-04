#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-3986: `java.lang.System.out` must exist next to `err`/`in` and
    /// write to stdout while `System.err` keeps writing to stderr.
    @Test
    func systemOutPrintlnWritesToStandardOutput() throws {
        try compileAndRunKotlin(
            """
            fun main(){System.out.println("ok");System.err.println("error")}
            """,
            expectedOutput: "ok\n",
            expectedErrorOutput: "error\n"
        )
    }

    /// KUU-3986: the print/println overload set must cover the common JVM
    /// types, and `PrintStream.printf`/`format` must format via the bundled
    /// String.format machinery.
    @Test
    func systemOutPrintfFormatsAndPrintOverloadsCoverCommonTypes() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                System.out.println(42)
                System.out.println(4.5)
                System.out.println(true)
                System.out.println('Z')
                System.out.println(charArrayOf('a', 'b'))
                System.out.println(null as Any?)
                System.out.print("x")
                System.out.print(7)
                System.out.println()
                System.out.printf("n=%d s=%s%n", 1, "two")
                System.out.printf("%5d|%-5d|%05d%n", 42, 42, 42)
                System.out.format("f=%d%n", 9)
                System.out.printf("%s", "chained").println()
            }
            """,
            expectedOutput: """
            42
            4.5
            true
            Z
            ab
            null
            x7
            n=1 s=two
               42|42   |00042
            f=9
            chained

            """
        )
    }

    /// KUU-3986: PrintStream.close() marks the stream closed; subsequent
    /// writes — including writes to System.out — are silently dropped like
    /// the JDK.
    @Test
    func systemOutCloseDropsSubsequentWrites() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val wrapped = java.io.ByteArrayOutputStream()
                val stream = java.io.PrintStream(wrapped)
                stream.print("a")
                stream.close()
                stream.print("dropped")
                System.out.println(wrapped.toString())
                System.out.close()
                System.out.println("dropped-too")
            }
            """,
            expectedOutput: "a\n"
        )
    }
}
#endif
