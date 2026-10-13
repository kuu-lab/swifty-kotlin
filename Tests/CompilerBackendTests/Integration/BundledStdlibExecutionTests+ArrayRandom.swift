import Testing

extension BundledStdlibExecutionTests {
    // KUU-1392: random()/randomOrNull() on Array<out T>, the eight primitive
    // arrays, and the four unsigned arrays — with and without a Random seed.
    // Assertions stay membership/contract based so output is deterministic.
    @Test(arguments: [true, false])
    func testArrayRandomOverloads(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.random.Random

            @OptIn(ExperimentalUnsignedTypes::class)
            fun unsignedChecks() {
                val uInts = uintArrayOf(4u, 8u, 15u)
                println(uInts.toList().contains(uInts.random()))
                println(uInts.toList().contains(uInts.random(Random(42))))
                println(uInts.randomOrNull() != null)
                println(uInts.toList().contains(uInts.randomOrNull(Random(7)) ?: 0u))
                println(uintArrayOf().randomOrNull() == null)
                println(ulongArrayOf(7uL).random() == 7uL)
                println(ubyteArrayOf(9u).randomOrNull(Random(3)) == 9u.toUByte())
                println(ushortArrayOf(11u).random() == 11u.toUShort())
                try {
                    ubyteArrayOf().random(Random(1))
                    println(false)
                } catch (e: NoSuchElementException) {
                    println(e.message)
                }
            }

            fun main() {
                val ints = intArrayOf(3, 1, 4, 1, 5, 9)
                println(ints.toList().contains(ints.random()))
                println(ints.toList().contains(ints.random(Random(42))))
                println(ints.randomOrNull() != null)
                println(ints.toList().contains(ints.randomOrNull(Random(7)) ?: -1))
                println(intArrayOf().randomOrNull() == null)
                try {
                    intArrayOf().random()
                    println(false)
                } catch (e: NoSuchElementException) {
                    println(e.message)
                }

                println(longArrayOf(2L).random() == 2L)
                println(byteArrayOf(5).randomOrNull() == 5.toByte())
                println(shortArrayOf(6).randomOrNull(Random(1)) == 6.toShort())
                println(charArrayOf('z').random() == 'z')
                println(booleanArrayOf(true).randomOrNull())
                println(floatArrayOf(1.5f).random() == 1.5f)
                println(doubleArrayOf(2.5).randomOrNull(Random(2)) == 2.5)

                val strings = arrayOf("a", "b", "c")
                println(strings.toList().contains(strings.randomOrNull() ?: "q"))
                println(strings.randomOrNull(Random(9)) != null)
                println(emptyArray<Int>().randomOrNull() == null)
                try {
                    emptyArray<Int>().random()
                    println(false)
                } catch (e: NoSuchElementException) {
                    println(e.message)
                }

                unsignedChecks()
            }
            """,
            expectedOutput: """
            true
            true
            true
            true
            true
            Array is empty.
            true
            true
            true
            true
            true
            true
            true
            true
            true
            true
            Array is empty.
            true
            true
            true
            true
            true
            true
            true
            true
            Array is empty.

            """,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
