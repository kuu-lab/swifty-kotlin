fun main() {
    val doubles: Sequence<Double> = sequenceOf(3.0, 1.0, 4.0)
    val minOfDouble: Double = doubles.minOf { it }
    val minOfOrNullDouble: Double? = doubles.minOfOrNull { it }

    val floats: Sequence<Float> = sequenceOf(3.0f, 1.0f, 4.0f)
    val minOfFloat: Float = floats.minOf { it }
    val minOfOrNullFloat: Float? = floats.minOfOrNull { it }

    val words: Sequence<String> = sequenceOf("aaa", "b", "cc")
    val cmp = Comparator<Int> { a, b -> a - b }
    val minOfWith: Int = words.minOfWith(cmp) { it.length }
    val minOfWithOrNull: Int? = words.minOfWithOrNull(cmp) { it.length }

    println(minOfDouble)
    println(minOfOrNullDouble)
    println(minOfFloat)
    println(minOfOrNullFloat)
    println(minOfWith)
    println(minOfWithOrNull)
}
