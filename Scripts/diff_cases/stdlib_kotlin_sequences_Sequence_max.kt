data class Item(val name: String, val score: Double)

fun main() {
    val doubles = sequenceOf(3.0, 1.0, 4.0, 1.5, 9.0)
    println(doubles.max())
    println(doubles.maxOrNull())

    val floats = sequenceOf(3.0f, 1.0f, 4.0f, 1.5f, 9.0f)
    println(floats.max())
    println(floats.maxOrNull())

    val withNaN = sequenceOf(1.0, Double.NaN, 2.0)
    println(withNaN.max())

    val ints = sequenceOf(3, 1, 4, 1, 5)
    println(ints.max())
    println(ints.maxOrNull())

    val words2 = sequenceOf("aaa", "b", "cc")
    println(words2.max())
    println(words2.maxOrNull())

    val items = sequenceOf(Item("a", 2.0), Item("b", 5.0), Item("c", 1.0))
    println(items.maxOf { it.score })
    println(items.maxOfOrNull { it.score })

    val floatItems = sequenceOf(Item("a", 2.0), Item("b", 5.0))
    println(floatItems.maxOf { it.score.toFloat() })

    val cmp = Comparator<Int> { a, b -> a - b }
    val words = sequenceOf("aaa", "b", "cc")
    println(words.maxOfWith(cmp) { it.length })
    println(words.maxOfWithOrNull(cmp) { it.length })

    println(emptySequence<Double>().maxOrNull())
    println(emptySequence<Float>().maxOrNull())
    try {
        emptySequence<Double>().max()
        println("no throw")
    } catch (e: NoSuchElementException) {
        println("threw NoSuchElementException")
    }
}
