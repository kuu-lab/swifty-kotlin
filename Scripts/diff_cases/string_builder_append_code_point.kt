// DIFF_JVM
// KUU-2040: preserve the independently typed reproducer and UTF-16 boundaries.
fun append(builder: StringBuilder, cp: Int): StringBuilder = builder.appendCodePoint(cp)

fun firstCodeUnit(text: String): Int = text[0].code
fun clear(builder: StringBuilder) { builder.delete(0, builder.length) }
fun resetLength(builder: StringBuilder) { builder.setLength(0) }

private fun codes(text: CharSequence): String {
    val result = StringBuilder()
    var index = 0
    while (index < text.length) {
        if (index > 0) result.append(',')
        result.append(text[index].code)
        index++
    }
    return result.toString()
}

fun main() {
    val points = intArrayOf(0, 1, 65, 0xE9, 0xD7FF, 0xD800, 0xDBFF, 0xDC00,
                           0xDFFF, 0xE000, 0xFFFF, 0x10000, 0x1F600, 0x10FFFF)
    for (cp in points) {
        val builder = StringBuilder("p")
        val returned = append(builder, cp)
        println("$cp:${builder.length}:${returned === builder}:${codes(builder)}:${codes(builder.toString())}")
    }

    // Invalid input must throw the JVM exception type before mutating the buffer.
    for (cp in intArrayOf(-1, 0x110000, Int.MIN_VALUE, Int.MAX_VALUE)) {
        val builder = StringBuilder("unchanged")
        val capacity = builder.capacity()
        try {
            append(builder, cp)
            println("missing-exception:$cp")
        } catch (e: IllegalArgumentException) {
            println("invalid:$cp:$builder:${builder.length}:${builder.capacity() == capacity}")
        }
    }

    val decimal = StringBuilder().append(65).appendCodePoint(65)
    println("decimal:$decimal")
    val chained = StringBuilder().appendCodePoint(65).appendCodePoint(0x1F600)
    println("chained:$chained:${chained.length}")
    println("implicit:" + buildString { appendCodePoint(0x1F600) })

    // Match xenocom's two call shapes: sb.appendCodePoint(codePoint) and
    // word.appendCodePoint(outputCodePoint), including the NBSP substitution.
    // https://github.com/xenomachina/xenocom/blob/745f41619f2e230b2705fa50835bb85ea6532963/src/main/kotlin/TextTerm.kt#L43
    // The second call is at line 123 of the same revision.
    val sb = StringBuilder()
    val word = StringBuilder()
    for (codePoint in intArrayOf(65, 0x1F600, 0xA0)) {
        sb.appendCodePoint(codePoint)
        val outputCodePoint = if (codePoint == 0xA0) ' '.code else codePoint
        word.appendCodePoint(outputCodePoint)
    }
    println("xenocom:${codes(sb)}:${codes(word)}")

    println("control:${firstCodeUnit("A")}")
    clear(sb)
    resetLength(word)
    println("cleared:${sb.length}:${word.length}")
}
