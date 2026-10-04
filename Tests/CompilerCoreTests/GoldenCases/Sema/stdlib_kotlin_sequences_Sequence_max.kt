fun main() {
    val doubles: Sequence<Double> = sequenceOf(3.0, 1.0, 4.0)
    val maxOfDouble: Double = doubles.maxOf { it }
    val maxOfOrNullDouble: Double? = doubles.maxOfOrNull { it }
    val maxDouble: Double = doubles.max()
    val maxOrNullDouble: Double? = doubles.maxOrNull()

    val floats: Sequence<Float> = sequenceOf(3.0f, 1.0f, 4.0f)
    val maxOfFloat: Float = floats.maxOf { it }
    val maxOfOrNullFloat: Float? = floats.maxOfOrNull { it }
    val maxFloat: Float = floats.max()
    val maxOrNullFloat: Float? = floats.maxOrNull()

    val ints: Sequence<Int> = sequenceOf(3, 1, 4)
    val maxInt: Int = ints.max()
    val maxOrNullInt: Int? = ints.maxOrNull()

    val words: Sequence<String> = sequenceOf("aaa", "b", "cc")
    val cmp = Comparator<Int> { a, b -> a - b }
    val maxOfWith: Int = words.maxOfWith(cmp) { it.length }
    val maxOfWithOrNull: Int? = words.maxOfWithOrNull(cmp) { it.length }
    val maxWord: String = words.max()
    val maxOrNullWord: String? = words.maxOrNull()

    println(maxOfDouble)
    println(maxOfOrNullDouble)
    println(maxDouble)
    println(maxOrNullDouble)
    println(maxOfFloat)
    println(maxOfOrNullFloat)
    println(maxFloat)
    println(maxOrNullFloat)
    println(maxInt)
    println(maxOrNullInt)
    println(maxOfWith)
    println(maxOfWithOrNull)
    println(maxWord)
    println(maxOrNullWord)
}
