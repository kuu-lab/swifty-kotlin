import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testFlowMissingOperators(artifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val f = flowOf(1, 2, 3)
                println(f.drop(1).toList())
                println(f.onStart { emit(0) }.toList())
                println(f.buffer().toList())
                println(f.first { it > 1 })
                println(f.toCollection(mutableListOf()))
            }
            """,
            expectedOutput: "[2, 3]\n[0, 1, 2, 3]\n[1, 2, 3]\n2\n[1, 2, 3]\n",
            allowDefaultStdlibLibrary: artifact
        )
    }

    @Test(arguments: [true, false])
    func testFlowMissingOperatorBoundaries(artifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_coroutines_flow_missing_operators.kt", file: #filePath),
            expectedOutput: """
            [2, 3]
            [2, 3]
            [1, 2, 3]
            []
            []
            negative drop
            constructed
            start
            upstream
            [0, 1]
            start
            upstream
            [0, 1]
            [4]
            start failed
            [1, 2, 3]
            [1, 2, 3]
            [1, 2, 3]
            negative buffer
            2
            2
            null
            no match
            empty
            predicate failed
            [1, 2, 3]
            true
            [9, 1, 2, 3]
            [9, 1, 2]
            true
            [1, null]

            """,
            allowDefaultStdlibLibrary: artifact
        )
    }
}
