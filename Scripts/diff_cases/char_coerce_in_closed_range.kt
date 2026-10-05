class CharBounds(
    override val start: Char,
    override val endInclusive: Char
) : ClosedRange<Char> {
    override fun toString(): String = "$start..$endInclusive"
}

fun <T : Comparable<T>> clamp(value: T, range: ClosedRange<T>): T = value.coerceIn(range)

fun emptyRangeMessage(range: ClosedRange<Char>): String? {
    return try {
        'c'.coerceIn(range)
        "did not throw"
    } catch (e: IllegalArgumentException) {
        e.message
    }
}

fun main() {
    println('a'.coerceIn('b'..'d'))
    println('z'.coerceIn('b'..'d'))
    println('c'.coerceIn('b'..'d'))
    println('a'.coerceIn('b', 'd'))
    val range: ClosedRange<Char> = 'b'..'d'
    println('a'.coerceIn(range))
    println('z'.coerceIn(range))
    println('b'.coerceIn(range))
    println('d'.coerceIn(range))
    println('a'.coerceIn('c'..'c'))
    println('z'.coerceIn('c'..'c'))
    println(clamp('a', range))
    println(clamp('z', range))
    val custom = CharBounds('b', 'd')
    println('a'.coerceIn(custom))
    println('z'.coerceIn(custom))
    println('c'.coerceIn(custom))
    println(emptyRangeMessage('d'..'b'))
    println(emptyRangeMessage(CharBounds('d', 'b')))
    println(0.toChar().coerceIn(32768.toChar()..65535.toChar()).code)
    println(65535.toChar().coerceIn(0.toChar()..32768.toChar()).code)
    val nullable: Char? = 'a'
    val absent: Char? = null
    println(nullable?.coerceIn(range))
    println(absent?.coerceIn(range))
    println(clamp("a", "b".."d"))
    println(clamp("z", "b".."d"))
    println(clamp(0, 1..3))
    println(clamp(4, 1..3))
}
