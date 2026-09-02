class OneShotIterable(private val values: List<Int>) : Iterable<Int> {
    private val sharedIterator = values.iterator()

    override fun iterator(): Iterator<Int> {
        return sharedIterator
    }
}

fun main() {
    val values: Iterable<Int> = listOf(1, 2, 2, 3, 4)
    val calls = mutableListOf<Int>()
    val partitioned = values.partition {
        calls.add(it)
        it % 2 == 0
    }
    println(partitioned.first)
    println(partitioned.second)
    println(calls)

    val (all, none) = (listOf(1, 2) as Iterable<Int>).partition { it > 0 }
    println(all)
    println(none)
    val (emptyFirst, emptySecond) = emptyList<Int>().partition { true }
    println(emptyFirst)
    println(emptySecond)
    val (singleFirst, singleSecond) = listOf(7).partition { it < 0 }
    println(singleFirst)
    println(singleSecond)

    val nullable: Iterable<String?> = listOf("a", null, "a", null)
    val nullablePartition = nullable.partition { it == null }
    println(nullablePartition.component1())
    println(nullablePartition.component2())

    val first = values.partition { true }
    val second = values.partition { true }
    println(first.first === second.first)
    println(values)

    val oneShot: Iterable<Int> = OneShotIterable(listOf(8, 9))
    println(oneShot.partition { it == 8 })
    println(oneShot.partition { true })

    val visited = mutableListOf<Int>()
    try {
        values.partition {
            visited.add(it)
            if (it == 2) throw IllegalStateException("stop")
            true
        }
        println("missing exception")
    } catch (e: IllegalStateException) {
        println("predicate exception")
    }
    println(visited)
}
