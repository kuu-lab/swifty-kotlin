// KSP-1387: source-backed kotlin.text.CharSequence.max-family parity.

private class TrackingCharSequence(initial: String) : CharSequence {
    private var content = initial
    var lengthReads = 0
    var characterReads = 0

    override val length: Int
        get() {
            lengthReads += 1
            return content.length
        }

    override fun get(index: Int): Char {
        characterReads += 1
        return content[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.substring(startIndex, endIndex)

    override fun toString(): String = "different display"
}

private fun describe(label: String, value: Any?) {
    println("$label=$value")
}

private fun nonLocalMaxBy(source: CharSequence, expected: Char): Char {
    source.maxBy {
        if (it == expected) return '!'
        it.code
    }
    return '?'
}

private fun capturedMaxBy(source: CharSequence, expected: Int): Char {
    source.maxBy { if (it.code == expected) return '!' else it.code }
    return '?'
}

private fun nullableMaxOfOrNull(source: CharSequence?, expected: Int): Int {
    return source?.maxOfOrNull {
        if (it.code == expected) return 17
        it.code
    } ?: -1
}

fun main() {
    val source: CharSequence = "aZb"
    describe("max", source.max())
    describe("maxBy", source.maxBy { it.code })
    describe("maxByOrNull", source.maxByOrNull { it.code })
    describe("maxOfDouble", source.maxOf { it.code.toDouble() / 10.0 })
    describe("maxOfFloat", source.maxOf { it.code.toFloat() / 10.0f })
    describe("maxOfComparable", source.maxOf { it.code })
    describe("maxOfOrNullDouble", source.maxOfOrNull { it.code.toDouble() / 10.0 })
    describe("maxOfOrNullFloat", source.maxOfOrNull { it.code.toFloat() / 10.0f })
    describe("maxOfOrNullComparable", source.maxOfOrNull { it.code })

    describe("maxOfDoubleNaN", "abc".maxOf {
        when (it) {
            'a' -> 1.0
            'b' -> Double.NaN
            else -> 2.0
        }
    }.isNaN())
    describe("maxOfFloatNaN", "abc".maxOf {
        when (it) {
            'a' -> 1.0f
            'b' -> Float.NaN
            else -> 2.0f
        }
    }.isNaN())
    describe("maxOfDoubleSignedZero", "ab".maxOf {
        if (it == 'a') -0.0 else 0.0
    }.toBits())
    describe("maxOfFloatSignedZero", "ab".maxOf {
        if (it == 'a') -0.0f else 0.0f
    }.toBits())

    var comparatorCalls = 0
    val charComparator = Comparator<Char> { a, b ->
        comparatorCalls += 1
        a.code - b.code
    }
    describe("maxWith", source.maxWith(charComparator))
    describe("maxWithCalls", comparatorCalls)

    comparatorCalls = 0
    describe("maxWithOrNull", source.maxWithOrNull(charComparator))
    describe("maxWithOrNullCalls", comparatorCalls)

    val valueComparator = Comparator<Int> { a, b ->
        comparatorCalls += 1
        a - b
    }
    comparatorCalls = 0
    describe("maxOfWith", source.maxOfWith(valueComparator) { it.code })
    describe("maxOfWithCalls", comparatorCalls)
    comparatorCalls = 0
    describe("maxOfWithOrNull", source.maxOfWithOrNull(valueComparator) { it.code })
    describe("maxOfWithOrNullCalls", comparatorCalls)

    val singleton: CharSequence = "x"
    var selectorCalls = 0
    describe("maxBySingleton", singleton.maxBy { selectorCalls += 1; it.code })
    describe("maxBySingletonCalls", selectorCalls)
    selectorCalls = 0
    describe("maxByOrNullSingleton", singleton.maxByOrNull { selectorCalls += 1; it.code })
    describe("maxByOrNullSingletonCalls", selectorCalls)

    val empty: CharSequence = ""
    try {
        empty.max()
        describe("maxEmpty", "missing")
    } catch (error: NoSuchElementException) {
        describe("maxEmpty", error.message)
    }
    describe("maxOrNullEmpty", empty.maxOrNull())
    describe("maxByOrNullEmpty", empty.maxByOrNull { it.code })
    describe("maxOfOrNullEmpty", empty.maxOfOrNull { it.code })
    describe("maxOfWithOrNullEmpty", empty.maxOfWithOrNull(valueComparator) { it.code })

    try {
        empty.maxWith(charComparator)
        describe("maxWithEmpty", "missing")
    } catch (error: NoSuchElementException) {
        describe("maxWithEmpty", error.message)
    }

    println("nonLocalMaxBy=${nonLocalMaxBy(source, 'Z')}")
    println("capturedMaxBy=${capturedMaxBy(source, 'Z'.code)}")
    println("nullableMaxOfOrNull=${nullableMaxOfOrNull(source, 'Z'.code)}")
    println("nullableMaxOfOrNullNull=${nullableMaxOfOrNull(null, 'Z'.code)}")

    val utf16: CharSequence = TrackingCharSequence("A\uD83D\uDE00B")
    describe("utf16Max", utf16.max().code)
    describe("utf16MaxOrNull", utf16.maxOrNull()?.code)
    describe("utf16MaxOf", utf16.maxOf { it.code })
    val tracked = utf16 as TrackingCharSequence
    describe("trackingLengthReads", tracked.lengthReads > 0)
    describe("trackingCharacterReads", tracked.characterReads > 0)
}
