import kotlin.time.Duration.Companion.days

fun capturedComparator(offset: Int): Comparator<String> = compareBy { it.length + offset }

fun printSelectorFailure(block: () -> Unit) {
    try {
        block()
        println("missing exception")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}

fun main() {
    val words = listOf("bb", "ccc", "a")
    println(words.sortedBy { it.length })
    println(words.sortedWith(compareBy { it.length }))
    println(words.sortedWith(compareBy<String> { it.length }))
    val comparator = compareBy<String> { it.length }
    println(comparator.compare("bb", "ccc"))
    println(comparator.compare("ccc", "a"))
    println(comparator.compare("bb", "zz"))
    println(compareValuesBy("bb", "ccc") { it.length })
    println(words.sortedWith(object : Comparator<String> {
        override fun compare(a: String, b: String): Int = a.length.compareTo(b.length)
    }))

    val stable = listOf("bb", "dd", "ccc", "a", "eee", "f")
    println(stable.sortedWith(compareBy { it.length }))
    println(stable.sortedWith(compareByDescending { it.length }))
    println(stable.sortedWith(compareBy<String> { it.length }.reversed()))
    println(stable.sortedWith(compareBy<String> { it.length }.thenBy { it }))
    println(stable.sortedWith(compareBy<String> { it.length }.thenByDescending { it }))
    println(stable.sortedWith(compareBy({ it.length }, { it })))
    println(stable.sortedWith(compareBy(reverseOrder<Int>()) { it.length }))

    val captured = capturedComparator(7)
    println(captured.compare("bb", "ccc"))
    println(stable.sortedWith(captured))
    val mutable = stable.toMutableList()
    mutable.sortWith(captured)
    println(mutable)
    println(stable.toTypedArray().sortedArrayWith(captured).joinToString(","))
    println(stable.asSequence().sortedWith(captured).toList())

    println(listOf("bb", null, "ccc", "a", null).sortedWith(compareBy { it?.length }))
    println(listOf("bb", null, "ccc", "a").sortedWith(nullsLast(compareBy { it.length })))
    println(listOf(3, -1, 0, 2).sortedWith(compareBy { it }))
    println(stable.sortedWith(compareBy { it.length.toLong() }))
    println(stable.sortedWith(compareBy { it.length.toDouble() }))
    println(stable.sortedWith(compareBy { it[0] }))
    println(stable.sortedWith(compareBy { it.length.days }))
    println(compareBy<String> { it.length.days }.compare("bb", "ccc"))

    var calls = 0
    val counted = compareBy<String> {
        calls += 1
        it.length
    }
    println(counted.compare("bb", "a"))
    println(calls)
    println(counted.compare("bb", "dd"))
    println(calls)

    val throwing = compareBy<String> {
        if (it == "bad") throw IllegalArgumentException("selector failed")
        it.length
    }
    printSelectorFailure { println(throwing.compare("bad", "a")) }
    printSelectorFailure { println(throwing.compare("a", "bad")) }
    printSelectorFailure { println(throwing.reversed().compare("bad", "a")) }
    printSelectorFailure { println(words.plus("bad").sortedWith(throwing)) }
    printSelectorFailure { println(nullsFirst(throwing).compare("bad", "a")) }
    printSelectorFailure { println(compareBy<String> { 0 }.then(throwing).compare("bad", "a")) }
    printSelectorFailure {
        println(words.sortedWith(compareByDescending { throw IllegalArgumentException("descending failed") }))
    }
    println(throwing.compare("bb", "a"))
    println(emptyList<String>().sortedWith(captured))
    println(listOf("bb").sortedWith(captured))
}
