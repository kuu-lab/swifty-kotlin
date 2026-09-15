fun main() {
    val doubles: Sequence<Double> = sequenceOf(3.0, 1.0, 4.0)
    val maxOfDouble: Double = doubles.maxOf { it }
    val maxOfOrNullDouble: Double? = doubles.maxOfOrNull { it }

    val floats: Sequence<Float> = sequenceOf(3.0f, 1.0f, 4.0f)
    val maxOfFloat: Float = floats.maxOf { it }
    val maxOfOrNullFloat: Float? = floats.maxOfOrNull { it }

    val words: Sequence<String> = sequenceOf("aaa", "b", "cc")
    val cmp = Comparator<Int> { a, b -> a - b }
    val maxOfWith: Int = words.maxOfWith(cmp) { it.length }
    val maxOfWithOrNull: Int? = words.maxOfWithOrNull(cmp) { it.length }

    println(maxOfDouble)
    println(maxOfOrNullDouble)
    println(maxOfFloat)
    println(maxOfOrNullFloat)
    println(maxOfWith)
    println(maxOfWithOrNull)
}
