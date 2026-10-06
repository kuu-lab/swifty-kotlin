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
            """
            import kotlinx.coroutines.runBlocking
            import kotlinx.coroutines.flow.*

            fun main() = runBlocking {
                val f = flowOf(1, 2, 3)
                val dropped = f.drop(1)
                println(dropped.toList())
                println(dropped.toList())
                println(f.drop(0).toList())
                println(f.drop(5).toList())
                println(emptyFlow<Int>().drop(1).toList())
                try {
                    f.drop(-1)
                } catch (e: IllegalArgumentException) {
                    println("negative drop")
                }

                val started = flow<Int> {
                    println("upstream")
                    emit(1)
                }.onStart {
                    println("start")
                    emit(0)
                }
                println("constructed")
                println(started.toList())
                println(started.toList())
                println(emptyFlow<Int>().onStart { emit(4) }.toList())
                try {
                    f.onStart { throw IllegalStateException("start failed") }.toList()
                } catch (e: IllegalStateException) {
                    println(e.message)
                }

                println(f.buffer().toList())
                println(f.buffer(0).toList())
                println(f.buffer(2).toList())
                try {
                    f.buffer(-3)
                } catch (e: IllegalArgumentException) {
                    println("negative buffer")
                }

                println(f.first { it > 1 })
                println(flow<Int> {
                    emit(1)
                    emit(2)
                    throw IllegalStateException("must not reach")
                }.first { it == 2 })
                println(flowOf<Int?>(1, null, 3).first { it == null })
                try {
                    f.first { it > 3 }
                } catch (e: NoSuchElementException) {
                    println("no match")
                }
                try {
                    emptyFlow<Int>().first { true }
                } catch (e: NoSuchElementException) {
                    println("empty")
                }
                try {
                    f.first { throw IllegalStateException("predicate failed") }
                } catch (e: IllegalStateException) {
                    println(e.message)
                }

                println(f.toCollection(mutableListOf()))
                val destination = mutableListOf(9)
                println(f.toCollection(destination) === destination)
                println(destination)
                println(flowOf(1, 1, 2).toCollection(linkedSetOf(9)))
                println(emptyFlow<Int>().toCollection(destination) === destination)
                println(flowOf<Int?>(1, null).toCollection(mutableListOf<Int?>()))
            }
            """,
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
