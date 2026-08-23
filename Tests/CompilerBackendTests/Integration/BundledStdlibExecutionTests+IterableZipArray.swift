import Testing

extension BundledStdlibExecutionTests {
    /// KSP-999: Array overloads must stop before consuming an extra element from
    /// an arbitrary Iterable, while preserving pair order and transform timing.
    @Test
    func testIterableZipArrayDoesNotPrefetchTail() throws {
        try compileAndRunKotlin(
            """
            private class OneShotIterator(
                private val values: Array<Int>,
                private val cursor: Array<Int>
            ) : Iterator<Int> {
                override fun hasNext(): Boolean = cursor[0] < values.size

                override fun next(): Int {
                    if (!hasNext()) throw NoSuchElementException()
                    val value = values[cursor[0]]
                    cursor[0] = cursor[0] + 1
                    return value
                }
            }

            private class OneShotIterable(
                private val values: Array<Int>,
                private val cursor: Array<Int>,
                private val iteratorCalls: Array<Int>
            ) : Iterable<Int> {
                override fun iterator(): Iterator<Int> {
                    if (iteratorCalls[0] != 0) throw IllegalStateException("iterator called twice")
                    iteratorCalls[0] = iteratorCalls[0] + 1
                    return OneShotIterator(values, cursor)
                }
            }

            fun main() {
                val pairCursor = arrayOf(0)
                val pairIteratorCalls = arrayOf(0)
                val pairSource = OneShotIterable(arrayOf(1, 2, 3), pairCursor, pairIteratorCalls)
                println(pairSource.zip(arrayOf<String?>("a", null)))
                println("pair:${pairCursor[0]}:${pairIteratorCalls[0]}")

                val transformCursor = arrayOf(0)
                val transformIteratorCalls = arrayOf(0)
                var transformCalls = 0
                val transformSource = OneShotIterable(arrayOf(4, 5, 6), transformCursor, transformIteratorCalls)
                println(transformSource.zip(arrayOf("x", "y")) { left, right ->
                    transformCalls = transformCalls + 1
                    "$left$right"
                })
                println("transform:${transformCursor[0]}:${transformIteratorCalls[0]}:$transformCalls")

                val exceptionCursor = arrayOf(0)
                val exceptionIteratorCalls = arrayOf(0)
                var exceptionCalls = 0
                try {
                    OneShotIterable(arrayOf(7, 8, 9), exceptionCursor, exceptionIteratorCalls)
                        .zip(arrayOf("p", "q", "r")) { left, right ->
                            exceptionCalls = exceptionCalls + 1
                            if (left == 8) throw IllegalStateException("stop")
                            "$left$right"
                        }
                } catch (e: IllegalStateException) {
                    println("exception:${exceptionCursor[0]}:${exceptionIteratorCalls[0]}:$exceptionCalls")
                }
            }
            """,
            expectedOutput: """
            [(1, a), (2, null)]
            pair:2:1
            [4x, 5y]
            transform:2:1:2
            exception:2:1:2

            """
        )
    }
}
