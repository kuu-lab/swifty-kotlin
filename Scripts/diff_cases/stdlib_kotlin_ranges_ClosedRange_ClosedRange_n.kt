class StringBounds(
    override val start: String,
    override val endInclusive: String,
) : ClosedRange<String>

class ExcludingBounds : ClosedRange<Int> {
    override val start: Int get() = 1
    override val endInclusive: Int get() = 5
    override fun contains(value: Int): Boolean = value == 42
    override fun isEmpty(): Boolean = true
}

fun inspect(range: ClosedRange<String>, value: String) {
    println(range.start)
    println(range.endInclusive)
    println(range.contains(value))
    println(value in range)
    println(range.isEmpty())
}

fun inspectInt(range: ClosedRange<Int>) {
    println(range.start)
    println(range.endInclusive)
    println(range.contains(3))
    println(4 in range)
    println(42 in range)
    println(42 !in range)
    println(range.isEmpty())
}

fun <T : Comparable<T>> inspectBounds(range: ClosedRange<T>, value: T) {
    println(range.start)
    println(range.endInclusive)
    println(range.contains(value))
    println(value in range)
    println(range.isEmpty())
}

fun main() {
    inspect(StringBounds("b", "d"), "b")
    inspect(StringBounds("b", "d"), "d")
    inspect(StringBounds("b", "d"), "a")
    inspect(StringBounds("z", "a"), "m")
    inspectInt(1..5)
    inspectInt(5..1)
    inspectInt(IntRange(2, 6))
    inspectInt(ExcludingBounds())
    inspectBounds(1L..5L, 3L)
    inspectBounds(LongRange(5L, 1L), 3L)
    inspectBounds('b'..'d', 'c')
    inspectBounds(CharRange('d', 'b'), 'c')
    inspectBounds(1u..5u, 3u)
    inspectBounds(5u..1u, 3u)
    inspectBounds(2147483648u..UInt.MAX_VALUE, UInt.MAX_VALUE)
    inspectBounds(1uL..5uL, 3uL)
    inspectBounds(ULongRange(5uL, 1uL), 3uL)
    inspectBounds(9223372036854775808uL..ULong.MAX_VALUE, ULong.MAX_VALUE)
}
