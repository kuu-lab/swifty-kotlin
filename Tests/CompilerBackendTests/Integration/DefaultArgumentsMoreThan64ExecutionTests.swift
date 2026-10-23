import Testing

@Suite(.serialized)
struct DefaultArgumentsMoreThan64ExecutionTests {
    @Test func evaluatesDefaultArgumentsAcrossMaskWords() throws {
        let parameters64 = (1 ... 64).map { "p\($0): Int = \($0)" }.joined(separator: ", ")
        let parameters70 = (1 ... 70).map { "p\($0): Int = \($0)" }.joined(separator: ", ")

        try compileAndRunKotlin(
            """
            fun Char.beforeMaskBoundary(\(parameters64)): Int = p64
            fun Char.afterMaskBoundary(\(parameters70)): Int = p65 * 100 + p70

            fun main() {
                println('x'.beforeMaskBoundary())
                println('x'.afterMaskBoundary())
            }
            """,
            expectedOutput: "64\n6570\n",
            moduleName: "KUU2863DefaultArgumentsMoreThan64"
        )
    }
}
