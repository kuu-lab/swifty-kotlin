import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testIteratorBuilderPreservesTopLevelStringAcrossYield() throws {
        try compileAndRunKotlin(
            """
            var trace = ""

            fun main() {
                println(iterator<Int> {
                    trace += "before;"
                    yield(1)
                    trace += "after;"
                    yield(2)
                }.asSequence().toList())
                println(trace)
            }
            """,
            expectedOutput: """
            [1, 2]
            before;after;

            """
        )
    }
}
