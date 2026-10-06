fun compareDoubleInt(a: Double, b: Int): Int = a.compareTo(b)
fun compareDoubleLong(a: Double, b: Long): Int = a.compareTo(b)
fun compareDoubleFloat(a: Double, b: Float): Int = a.compareTo(b)
fun compareFloatInt(a: Float, b: Int): Int = a.compareTo(b)
fun compareFloatLong(a: Float, b: Long): Int = a.compareTo(b)
fun compareFloatDouble(a: Float, b: Double): Int = a.compareTo(b)
fun <T : Comparable<T>> compareGeneric(a: T, b: T): Int = a.compareTo(b)

fun receiver(): Float {
    println("receiver")
    return 1.5f
}

fun argument(): Double {
    println("argument")
    return 2.0
}

fun main() {
    println(1.5.compareTo(2))
    println(1.5.compareTo(2L))
    println(2.0.compareTo(3))
    println(1.5f.compareTo(2))
    println(1.5f.compareTo(2.0))
    println(2.0.compareTo(4607182418800017408L))
    println(0.9.compareTo(4607182418800017408L))

    println(compareDoubleInt(1.5, 2))
    println(compareDoubleLong(1.5, 2L))
    println(compareDoubleFloat(1.5, 2f))
    println(compareFloatInt(1.5f, 2))
    println(compareFloatLong(1.5f, 2L))
    println(compareFloatDouble(1.5f, 2.0))

    val byte: Byte = 2
    val short: Short = 2
    println(1.5.compareTo(byte))
    println(1.5.compareTo(short))
    println(1.5f.compareTo(byte))
    println(1.5f.compareTo(short))

    println(compareDoubleInt(-1.5, -2))
    println(compareDoubleLong(-1.5, -2L))
    println(compareDoubleFloat(-1.5, -2f))
    println(compareFloatInt(-1.5f, -2))
    println(compareFloatLong(-1.5f, -2L))
    println(compareFloatDouble(-1.5f, -2.0))
    println(compareDoubleInt(2.0, 2))
    println(compareFloatLong(2f, 2L))
    println(compareFloatDouble(2f, 2.0))

    println(compareDoubleLong(9007199254740992.0, 9007199254740993L))
    println(compareFloatInt(16777216f, 16777217))
    println(compareFloatLong(16777216f, 16777217L))
    println(compareFloatDouble(16777216f, 16777217.0))
    println(compareDoubleFloat(16777217.0, 16777216f))
    println(compareDoubleLong(0.0, Long.MIN_VALUE))
    println(compareFloatLong(0f, Long.MAX_VALUE))

    println(Double.NaN.compareTo(2))
    println(Float.NaN.compareTo(2L))
    println(Float.NaN.compareTo(Double.NaN))
    println(Double.NaN.compareTo(Float.NaN))
    println(Float.POSITIVE_INFINITY.compareTo(Long.MAX_VALUE))
    println(Double.NEGATIVE_INFINITY.compareTo(Long.MIN_VALUE))
    println(compareFloatDouble(1f, Double.POSITIVE_INFINITY))
    println(compareDoubleFloat(1.0, Float.NEGATIVE_INFINITY))
    println((-0.0).compareTo(0))
    println((-0.0f).compareTo(0L))
    println((-0.0f).compareTo(0.0))
    println(0.0.compareTo(-0.0f))

    val comparator: (Float, Double) -> Int = { a, b -> a.compareTo(b) }
    println(comparator(1.5f, 2.0))
    println(receiver().compareTo(argument()))
    val present: Float? = 1.5f
    val absent: Float? = null
    println(present?.compareTo(argument()))
    println(absent?.compareTo(argument()))

    println(1.5.compareTo(2.0))
    println(1.5f.compareTo(2f))
    println(1.compareTo(1.5))
    println(2L.compareTo(1.5))
    println(1.5 < 2)
    println(1.5f < 2.0)
    println(compareGeneric(1.5, 2.0))
    println(compareGeneric(1.5f, 2f))
    println(minOf(1.5, 2.0).compareTo(1.5))
    println(maxOf(1.5f, 2f).compareTo(2f))
    val values = listOf(2.5f, 1.5f, 3.5f)
    println(values.sortedWith(Comparator { a, b -> a.compareTo(b.toDouble()) }).joinToString(","))
}
