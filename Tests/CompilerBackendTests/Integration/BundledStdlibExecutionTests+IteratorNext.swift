import Testing

extension BundledStdlibExecutionTests {
    /// KUU-647: `Iterator.next()` after exhaustion must throw `NoSuchElementException`
    /// instead of returning a silent `0`.
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
}
