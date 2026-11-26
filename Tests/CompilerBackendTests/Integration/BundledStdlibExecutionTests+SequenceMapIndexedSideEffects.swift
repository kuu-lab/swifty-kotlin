import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testSequenceMapIndexedAndWithIndexSourceHasNextCount() throws {
        try compileAndRunKotlin(
            """
            class CS<out T>(private val s: Sequence<T>) : Sequence<T> {
                var c = 0
                inner class I(private val it: Iterator<T>) : Iterator<T> {
                    override fun hasNext() = it.hasNext().also { c++ }
                    override fun next() = it.next()
                }
                override fun iterator() = I(s.iterator())
            }
            fun main() {
                val xs = CS(listOf("a","b").asSequence())
                for ([i, x] in xs.withIndex()) { }
                println("withIndex=${xs.c}")
                val ys = CS(listOf("a","b","c","d").asSequence())
                for (e in ys.mapIndexed { index, value -> value }) { }
                println("mapIndexed=${ys.c}")
                println(CS(listOf("a").asSequence()).withIndex().toList())
            }
            """,
            expectedOutput: "withIndex=3\nmapIndexed=5\n[IndexedValue(index=0, value=a)]\n",
            moduleName: "KUU3809SequenceMapIndexedHasNext"
        )
    }
}
