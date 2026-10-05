fun byteComparisons(b: Byte, other: Byte, s: Short, i: Int, l: Long, f: Float, d: Double) {
    println(b.compareTo(other))
    println(b.compareTo(s))
    println(b.compareTo(i))
    println(b.compareTo(l))
    println(b.compareTo(f))
    println(b.compareTo(d))
}

fun shortComparisons(s: Short, b: Byte, other: Short, i: Int, l: Long, f: Float, d: Double) {
    println(s.compareTo(b))
    println(s.compareTo(other))
    println(s.compareTo(i))
    println(s.compareTo(l))
    println(s.compareTo(f))
    println(s.compareTo(d))
}

fun <T : Comparable<T>> compareGeneric(a: T, b: T): Int = a.compareTo(b)

fun Byte.compareTo(other: String): Int = other.length
fun Short.compareTo(other: Boolean): Int = if (other) 7 else 8

fun receiver(value: Byte?): Byte? {
    println("receiver")
    return value
}

fun argument(): Double {
    println("argument")
    return 2.0
}

fun main() {
    val b: Byte = 1
    val s: Short = 2
    println(b.compareTo(s))
    println(1.toByte().compareTo(2))
    println(1.toShort().compareTo(2))

    byteComparisons(1, 2, 2, 2, 2L, 1.5f, 1.5)
    byteComparisons(2, 1, 1, 1, 1L, 1.5f, 1.5)
    byteComparisons(-128, -128, -128, -128, -128L, -128f, -128.0)
    byteComparisons(127, -128, -32768, Int.MIN_VALUE, Long.MIN_VALUE, Float.NEGATIVE_INFINITY, Double.NEGATIVE_INFINITY)
    byteComparisons(-128, 127, 32767, Int.MAX_VALUE, Long.MAX_VALUE, Float.POSITIVE_INFINITY, Double.POSITIVE_INFINITY)
    byteComparisons(0, 0, 0, 0, 0L, -0.0f, -0.0)
    byteComparisons(1, 1, 1, 1, 1L, Float.NaN, Double.NaN)

    shortComparisons(2, 1, 3, 3, 3L, 2.5f, 2.5)
    shortComparisons(3, 2, 2, 2, 2L, 2.5f, 2.5)
    shortComparisons(-128, -128, -128, -128, -128L, -128f, -128.0)
    shortComparisons(32767, -128, -32768, Int.MIN_VALUE, Long.MIN_VALUE, Float.NEGATIVE_INFINITY, Double.NEGATIVE_INFINITY)
    shortComparisons(-32768, 127, 32767, Int.MAX_VALUE, Long.MAX_VALUE, Float.POSITIVE_INFINITY, Double.POSITIVE_INFINITY)
    shortComparisons(0, 0, 0, 0, 0L, -0.0f, -0.0)
    shortComparisons(1, 1, 1, 1, 1L, Float.NaN, Double.NaN)
    println(Short.MAX_VALUE.compareTo(65536L))
    println(Short.MIN_VALUE.compareTo(-32768.5f))
    println(Short.MAX_VALUE.compareTo(32767.5))

    println(receiver(1)?.compareTo(argument()))
    println(receiver(null)?.compareTo(argument()))
    val short: Short? = -32768
    println(short?.compareTo(Long.MAX_VALUE))
    println(short?.compareTo(-32768.5f))
    val absent: Short? = null
    println(absent?.compareTo(argument()))
    val comparator: (Byte, Double) -> Int = { a, b -> a.compareTo(b) }
    println(comparator(-128, -127.5))

    println(compareGeneric(Byte.MIN_VALUE, Byte.MAX_VALUE))
    println(compareGeneric(Short.MAX_VALUE, Short.MIN_VALUE))
    val byteComparable: Comparable<Byte> = Byte.MIN_VALUE
    val shortComparable: Comparable<Short> = Short.MAX_VALUE
    println(byteComparable.compareTo(Byte.MAX_VALUE))
    println(shortComparable.compareTo(Short.MIN_VALUE))
    println(b < s)
    println(b > 0)
    println(b == 1.toByte())
    println(1.compareTo(s))
    println(2L.compareTo(b))
    println(1.compareTo(1.5))
    println(2L.compareTo(2.5f))
    println(b.compareTo("abcd"))
    println(s.compareTo(true))
}
