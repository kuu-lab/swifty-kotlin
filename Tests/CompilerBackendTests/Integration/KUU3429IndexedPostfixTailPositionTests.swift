import Testing

@Suite
struct KUU3429IndexedPostfixTailPositionTests {
    @Test
    func indexedPostfixMutationAtLambdaTailReturnsOldValue() throws {
        try compileAndRunKotlin(
            """
            operator fun String.inc() = this + "i"
            operator fun String.dec() = this + "d"

            object A {
                var x = "s"
                operator fun get(vararg a: String): String { return x }
                operator fun set(vararg a: String, value: String) { x = value }
            }

            fun main() {
                val increment = { A["m"]++ }
                println(increment())
                println(A.x)

                val decrement = { A["n"]-- }
                println(decrement())
                println(A.x)
            }
            """,
            expectedOutput: "s\nsi\nsi\nsid\n",
            moduleName: "KUU3429IndexedPostfixTail"
        )
    }
}
