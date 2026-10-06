import Testing

extension BundledStdlibExecutionTests {
    // KUU-1256: exercise both imported metadata and bundled source resolution.
    @Test(arguments: [true, false])
    func testArrayIterableExtensions(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun Array<Int>.zip(other: String): String = other

            private fun inlineArrayReturn(): Int {
                arrayOf(7).forEachIndexed { _, value -> return value }
                return 0
            }

            private class MutatingArrayIterable(private val array: Array<Int>) : Iterable<Int> {
                var pulls = 0
                override fun iterator(): Iterator<Int> = object : Iterator<Int> {
                    private var index = 0
                    override fun hasNext(): Boolean = index < 2
                    override fun next(): Int {
                        pulls++
                        array[0] = 9
                        return ++index
                    }
                }
            }

            fun main() {
                println(inlineArrayReturn())
                println(arrayOf(1).zip("user"))
                val dropLive = arrayOf(1, 2)
                println(dropLive.dropWhile { dropLive[0] = 9; false })
                val zipLive = arrayOf(1)
                val zipOther = MutatingArrayIterable(zipLive)
                println(zipLive.zip(zipOther))
                println(zipOther.pulls)
                val zipTransformLive = arrayOf(1)
                val zipTransformOther = MutatingArrayIterable(zipTransformLive)
                println(zipTransformLive.zip(zipTransformOther) { left, right -> left + right })
                println(zipTransformOther.pulls)
                val zipEmpty = MutatingArrayIterable(arrayOf(1))
                println(emptyArray<Int>().zip(zipEmpty))
                println(zipEmpty.pulls)
                val a = arrayOf(1, 2, 3, 2)
                println(a.take(2))
                println(a.takeLast(2))
                println(a.takeWhile { it < 3 })
                println(a.drop(2))
                println(a.dropLast(2))
                println(a.dropWhile { it < 3 })
                println(a.slice(1..2))
                println(a.slice(listOf(3, 0, 3)))
                println(a.elementAt(2))
                println(a.elementAtOrNull(-1))
                println(a.elementAtOrNull(4))
                println(a.elementAtOrElse(8) { -it })
                println(a.getOrElse(-2) { -it })
                println(a.single { it == 3 })
                println(a.singleOrNull { it == 2 })
                println(arrayOf(7).random())
                println(a.sum())
                println(a.average())
                println(a.min())
                println(a.max())
                println(a.minOrNull())
                println(a.maxOrNull())
                println(a.foldRight("end") { value, acc -> "$value:$acc" })
                println(a.reduceRight { value, acc -> value - acc })
                println(a.reduceRight<Any, Int> { value, acc -> if (value == 2) acc else value })
                val widened: Any = a.reduceRight { value: Int, acc: Any -> if (value == 2) acc else "wide" }
                println(widened)
                println(a.scan(0) { acc, value -> acc + value })
                println(a.runningFold(10) { acc, value -> acc + value })
                println(a.distinct())
                println(a.toSet())
                println(a.toHashSet().size)
                println(a.toMutableSet())
                val target = mutableListOf(9)
                println(a.toCollection(target) === target)
                println(target)
                println(a.mapTo(mutableListOf(8)) { it * 2 })
                println(a.filterTo(mutableListOf(8)) { it > 1 })
                println(a.flatMapTo(mutableListOf(8)) { listOf(it, -it) })
                println(a.asIterable().toList())
                println(a.partition { it % 2 == 0 })
                println(a.groupBy { it % 2 })
                println(a.groupBy({ it % 2 }, { it * 10 }))
                a.forEachIndexed { index, value -> println("$index:$value") }
                println(arrayOf(7).single())
                println(a.singleOrNull())
                println(a.zip(listOf("a", "b")))
                println(a.zip(listOf("a", "b")) { left, right -> "$left$right" })
                println(a.zip(arrayOf("a", "b")))
                println(a.zip(arrayOf("a", "b")) { left, right -> "$left$right" })
                println(a.flatMapTo(mutableListOf<Int>()) { sequenceOf(it, -it) })
                println(arrayOf(1.0, Double.NaN, 2.0).min().isNaN())
                println(arrayOf(1.0, Double.NaN, 2.0).maxOrNull()!!.isNaN())
                println(1.0 / arrayOf(0.0, -0.0).min())
                println(1.0 / arrayOf(-0.0, 0.0).max())
                println(arrayOf(1.0f, Float.NaN, 2.0f).minOrNull()!!.isNaN())
                println(arrayOf(1.0f, Float.NaN, 2.0f).max().isNaN())
                val empty = emptyArray<Int>()
                println(empty.take(3))
                println(empty.drop(3))
                println(empty.slice(2..1))
                println(empty.minOrNull())
                println(empty.maxOrNull())
                println(empty.sum())
                println(empty.average().isNaN())
                println(empty.runningFold(5) { acc, value -> acc + value })
                println(empty.zip(a))
                println(arrayOf<String?>(null, "x", null).distinct())
                println(arrayOf<String?>(null, "x").elementAtOrElse(0) { "fallback" })
                println(arrayOf<String?>(null, "x").single { it == null })
                val singleLive = arrayOf(1, 2)
                println(singleLive.single { singleLive[0] = 9; it == 1 })
                val singleOrNullLive = arrayOf(1, 2)
                println(singleOrNullLive.singleOrNull { singleOrNullLive[0] = 9; it == 1 })
                val live = arrayOf(1, 2)
                val view = live.asIterable()
                live[0] = 7
                println(view.toList())
                println(live.mapTo(mutableListOf<Int>()) { live[1] = 9; it })
                try { a.take(-1) } catch (e: IllegalArgumentException) { println("negative take") }
                try { a.drop(-1) } catch (e: IllegalArgumentException) { println("negative drop") }
                try { a.elementAt(4) } catch (e: IndexOutOfBoundsException) { println("bounds") }
                try { empty.reduceRight { x, y -> x + y } } catch (e: UnsupportedOperationException) { println(e.message) }
                try { empty.random() } catch (e: NoSuchElementException) { println(e.message) }
                try { empty.min() } catch (e: NoSuchElementException) { println("empty min") }
                try { a.single { it == 2 } } catch (e: IllegalArgumentException) { println("multiple") }
                try { a.single { it == 9 } } catch (e: NoSuchElementException) { println("absent") }
                println(arrayOf(1L, 2L, 3L).sum())
                println(arrayOf(1L, 2L, 3L).average())
                println(arrayOf(1.5, 2.5).sum())
                println(arrayOf(1.5, 2.5).average())
                println(arrayOf(1.5f, 2.5f).sum())
                println(arrayOf(1.5f, 2.5f).average())
                println(arrayOf(1.toByte(), 2.toByte()).sum())
                println(arrayOf(1.toByte(), 2.toByte()).average())
                println(arrayOf(1.toShort(), 2.toShort()).sum())
                println(arrayOf(1.toShort(), 2.toShort()).average())
            }
            """,
            expectedOutput: """
            7
            user
            [1, 2]
            [(9, 1)]
            2
            [10]
            2
            []
            1
            [1, 2]
            [3, 2]
            [1, 2]
            [3, 2]
            [1, 2]
            [3, 2]
            [2, 3]
            [2, 1, 2]
            3
            null
            null
            -8
            2
            3
            null
            7
            8
            2.0
            1
            3
            1
            3
            1:2:3:2:end
            0
            1
            wide
            [0, 1, 3, 6, 8]
            [10, 11, 13, 16, 18]
            [1, 2, 3]
            [1, 2, 3]
            3
            [1, 2, 3]
            true
            [9, 1, 2, 3, 2]
            [8, 2, 4, 6, 4]
            [8, 2, 3, 2]
            [8, 1, -1, 2, -2, 3, -3, 2, -2]
            [1, 2, 3, 2]
            ([2, 2], [1, 3])
            {1=[1, 3], 0=[2, 2]}
            {1=[10, 30], 0=[20, 20]}
            0:1
            1:2
            2:3
            3:2
            7
            null
            [(1, a), (2, b)]
            [1a, 2b]
            [(1, a), (2, b)]
            [1a, 2b]
            [1, -1, 2, -2, 3, -3, 2, -2]
            true
            true
            -Infinity
            Infinity
            true
            true
            []
            []
            []
            null
            null
            0
            true
            [5]
            []
            [null, x]
            null
            null
            1
            1
            [7, 2]
            [7, 9]
            negative take
            negative drop
            bounds
            Empty array can't be reduced.
            Array is empty.
            empty min
            multiple
            absent
            6
            2.0
            4.0
            2.0
            4.0
            2.0
            3
            1.5
            3
            1.5

            """,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
