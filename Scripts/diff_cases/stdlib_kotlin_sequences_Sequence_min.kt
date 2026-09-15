data class Item(val name: String, val score: Double)

fun main() {
    val doubles = sequenceOf(3.0, 1.0, 4.0, 1.5, 9.0)
    println(doubles.min())
    println(doubles.minOrNull())

    val items = sequenceOf(Item("a", 2.0), Item("b", 5.0), Item("c", 1.0))
    println(items.minOf { it.score })
    println(items.minOfOrNull { it.score })

    val floatItems = sequenceOf(Item("a", 2.0), Item("b", 5.0))
    println(floatItems.minOf { it.score.toFloat() })

    val cmp = Comparator<Int> { a, b -> a - b }
    val words = sequenceOf("aaa", "b", "cc")
    println(words.minOfWith(cmp) { it.length })
    println(words.minOfWithOrNull(cmp) { it.length })

    println(emptySequence<Double>().minOrNull())
    try {
        emptySequence<Double>().min()
        println("no throw")
    } catch (e: NoSuchElementException) {
        println("threw NoSuchElementException")
    }
}
