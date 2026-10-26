import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testStringBuilderCodePointMethodsUseUTF16(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            #"""
            fun main() {
                val builder = StringBuilder("A\uD83D\uDE00B")
                println(builder.length)
                println(builder.codePointAt(0))
                println(builder.codePointAt(1))
                println(builder.codePointAt(2))
                println(builder.codePointBefore(3))
                println(builder.codePointBefore(4))
                println(builder.codePointCount(0, 4))
                println(builder.codePointCount(1, 3))
                println(builder.codePointCount(1, 2))
            }
            """#,
            expectedOutput: "4\n65\n128512\n56832\n128512\n66\n3\n1\n1\n",
            moduleName: "KUU3473StringBuilderCodePoints",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
