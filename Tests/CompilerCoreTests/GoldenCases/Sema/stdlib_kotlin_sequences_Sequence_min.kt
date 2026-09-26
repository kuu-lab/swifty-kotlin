fun main() {
    val doubles: Sequence<Double> = sequenceOf(3.0, 1.0, 4.0)
    val minOfDouble: Double = doubles.minOf { it }
    val minOfOrNullDouble: Double? = doubles.minOfOrNull { it }
    val minDouble: Double = doubles.min()
    val minOrNullDouble: Double? = doubles.minOrNull()

    val floats: Sequence<Float> = sequenceOf(3.0f, 1.0f, 4.0f)
    val minOfFloat: Float = floats.minOf { it }
    val minOfOrNullFloat: Float? = floats.minOfOrNull { it }
    val minFloat: Float = floats.min()
    val minOrNullFloat: Float? = floats.minOrNull()

    val ints: Sequence<Int> = sequenceOf(3, 1, 4)
    val minInt: Int = ints.min()
    val minOrNullInt: Int? = ints.minOrNull()

    val words: Sequence<String> = sequenceOf("aaa", "b", "cc")
    val cmp = Comparator<Int> { a, b -> a - b }
    val minOfWith: Int = words.minOfWith(cmp) { it.length }
    val minOfWithOrNull: Int? = words.minOfWithOrNull(cmp) { it.length }
    val minWord: String = words.min()
    val minOrNullWord: String? = words.minOrNull()

    println(minOfDouble)
    println(minOfOrNullDouble)
    println(minDouble)
    println(minOrNullDouble)
    println(minOfFloat)
    println(minOfOrNullFloat)
    println(minFloat)
    println(minOrNullFloat)
    println(minInt)
    println(minOrNullInt)
    println(minOfWith)
    println(minOfWithOrNull)
    println(minWord)
    println(minOrNullWord)
}
