import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testObjectLiteralCapturesPrimaryConstructorProperty(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            class Counter(private val limit: Int) : MutableIterable<Int> {
                override fun iterator(): MutableIterator<Int> {
                    return object : MutableIterator<Int> {
                        var index = 0

                        override fun hasNext(): Boolean = index < limit
                        override fun next(): Int = index++
                        override fun remove() {}
                    }
                }
            }

            fun main() {
                val iterator: MutableIterator<Int> = Counter(3).iterator()
                println(iterator.hasNext())
                println(iterator.next())
                println(iterator.hasNext())
                println(iterator.next())
                println(iterator.hasNext())
                println(iterator.next())
                println(iterator.hasNext())
            }
            """,
            expectedOutput: "true\n0\ntrue\n1\ntrue\n2\nfalse\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
