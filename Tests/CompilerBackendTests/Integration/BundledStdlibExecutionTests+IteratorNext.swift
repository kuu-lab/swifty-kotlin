import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testIteratorNextPastEndThrowsNoSuchElementException() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val listIt = listOf(1).iterator()
                println("first=${listIt.next()}")
                try {
                    println("second=${listIt.next()}")
                } catch (e: NoSuchElementException) {
                    println("list-caught")
                }

                val rangeIt = (1..1).iterator()
                println("range=${rangeIt.next()}")
                try {
                    rangeIt.next()
                } catch (e: NoSuchElementException) {
                    println("range-caught")
                }

                val mapIt = mapOf("a" to 1).keys.iterator()
                println("map=${mapIt.next()}")
                try {
                    mapIt.next()
                } catch (e: NoSuchElementException) {
                    println("map-caught")
                }
            }
            """,
            expectedOutput: """
            first=1
            list-caught
            range=1
            range-caught
            map=a
            map-caught

            """
        )
    }

    @Test
    func testForwardDeclaredClassReturnedThroughInterfaceDispatchesCorrectly() throws {
        try compileAndRunKotlin(
            """
            fun makeIter(): Iterator<String> = ForwardIter()

            fun makeCounted(): Counter = ForwardCounter(3)

            private class ForwardIter : Iterator<String> {
                private var i = 0
                override fun hasNext(): Boolean = i < 2
                override fun next(): String {
                    i++
                    return "x" + i
                }
            }

            interface Counter {
                fun count(): Int
                fun label(): String
            }

            private class ForwardCounter(private var n: Int) : Counter {
                override fun count(): Int = n
                override fun label(): String = "n=" + n
            }

            fun main() {
                val it = makeIter()
                while (it.hasNext()) println("got=" + it.next())
                val c = makeCounted()
                println("count=" + c.count() + ",label=" + c.label())
            }
            """,
            expectedOutput: """
            got=x1
            got=x2
            count=3,label=n=3

            """
        )
    }
}
