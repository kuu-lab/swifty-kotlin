import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testIterableFactoryNamedArgumentIsLazyAndRepeatable(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                var calls = 0
                val values: Iterable<Int> = Iterable(iterator = {
                    calls++
                    listOf(1, 2).iterator()
                })
                println(calls)
                val first = values.iterator()
                val second = values.iterator()
                println(first.next())
                println(second.next())
                println(first.next())
                println(second.next())
                println(first.hasNext())
                println(second.hasNext())
                println(values.toList())
                println(values.toList())
                println(calls)
                val empty = Iterable<String>(iterator = { emptyList<String>().iterator() })
                println(empty.toList())
                println(Iterable<Int>({ listOf(7).iterator() }).toList())
                println(Iterable { listOf(8).iterator() }.toList())
            }
            """,
            expectedOutput: """
            0
            1
            1
            2
            2
            false
            false
            [1, 2]
            [1, 2]
            4
            []
            [7]
            [8]

            """,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
