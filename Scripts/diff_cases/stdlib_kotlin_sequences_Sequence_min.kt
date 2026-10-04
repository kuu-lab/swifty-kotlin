data class Item(val name: String, val score: Double)

fun main() {
    val doubles = sequenceOf(3.0, 1.0, 4.0, 1.5, 9.0)
    println(doubles.min())
    println(doubles.minOrNull())

    val floats = sequenceOf(3.0f, 1.0f, 4.0f, 1.5f, 9.0f)
    println(floats.min())
    println(floats.minOrNull())

    val withNaN = sequenceOf(1.0, Double.NaN, 2.0)
    println(withNaN.min())

    val ints = sequenceOf(3, 1, 4, 1, 5)
    println(ints.min())
    println(ints.minOrNull())

    val words2 = sequenceOf("aaa", "b", "cc")
    println(words2.min())
    println(words2.minOrNull())

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
    println(emptySequence<Float>().minOrNull())
    try {
        emptySequence<Double>().min()
        println("no throw")
    } catch (e: NoSuchElementException) {
        println("threw NoSuchElementException")
    }
}
