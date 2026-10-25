import Testing

@Suite(.serialized)
struct UnaryPlusMutableLocalAliasTests {
    /// KUU-3098: unary `+` forwarded its operand's KIR id verbatim, so `+n`
    /// on a bare local read aliased that local's storage register instead of
    /// snapshotting its value. A `val a = +b` initializer then observed `b`'s
    /// later reassignment, `+b + b++` evaluated the lhs after the increment,
    /// `return +b` saw a mutating `finally`'s write, and `var a = +b` let a
    /// write to `a` corrupt `b`.
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
