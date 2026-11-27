import Testing

@Suite(.serialized)
struct UnaryPlusMutableLocalAliasTests {
    @Test(arguments: [true, false])
    func unaryPlusOnLocalSnapshotsValue(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun combine(a: Int, b: Int): String = "$a,$b"

            fun returnBeforeFinally(): Int {
                var n = 10
                try {
                    return +n
                } finally {
                    n = 20
                }
            }

            fun main() {
                var n = 10
                val saved = +n
                n = 20
                println(saved)

                n = 10
                println(+n + n++)

                println(returnBeforeFinally())

                val m = 10
                var mutableSaved = +m
                mutableSaved = 20
                println(m)

                var p = 10
                println(combine(+p, p++))
            }
            """,
            expectedOutput: "10\n20\n10\n10\n10,10\n",
            moduleName: "KUU3098UnaryPlusAlias",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
