private class CustomCharSequence(private val content: String) : CharSequence {
    override val length: Int
        get() = content.length

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.subSequence(startIndex, endIndex)
}

private fun report(label: String, value: Any?) {
    println("$label=$value")
}

private fun exercise(source: CharSequence) {
    val reverseChars = Comparator<Char> { left, right -> right.compareTo(left) }
    val reverseInts = Comparator<Int> { left, right -> right.compareTo(left) }

    report("min", source.min())
    report("minBy", source.minBy { it.code })
    report("minByOrNull", source.minByOrNull { it.code })
    report("minOfDouble", source.minOf { it.code.toDouble() })
    report("minOfFloat", source.minOf { it.code.toFloat() })
    report("minOfComparable", source.minOf { it.code })
    report("minOfOrNullDouble", source.minOfOrNull { it.code.toDouble() })
    report("minOfOrNullFloat", source.minOfOrNull { it.code.toFloat() })
    report("minOfOrNullComparable", source.minOfOrNull { it.code })
    report("minOfWith", source.minOfWith(reverseInts) { it.code })
    report("minOfWithOrNull", source.minOfWithOrNull(reverseInts) { it.code })
    report("minOrNull", source.minOrNull())
    report("minWithReverse", source.minWith(reverseChars))
    report("minWithOrNullReverse", source.minWithOrNull(reverseChars))
}

private fun throwsNoSuchElement(action: () -> Unit): Boolean {
    return try {
        action()
        false
    } catch (_: NoSuchElementException) {
        true
    }
}

fun main() {
    exercise("cBa")
    exercise(StringBuilder("cBa"))
    exercise(CustomCharSequence("cBa"))

    val empty: CharSequence = ""
    println("empty-minByOrNull=${empty.minByOrNull { it.code }}")
    println("empty-minOfOrNull=${empty.minOfOrNull { it.code }}")
    println("empty-minOfWithOrNull=${empty.minOfWithOrNull(Comparator<Int> { a, b -> a.compareTo(b) }) { it.code }}")
    println("empty-minOrNull=${empty.minOrNull()}")
    println("empty-minWithOrNull=${empty.minWithOrNull(Comparator<Char> { a, b -> a.compareTo(b) })}")
    println("throws-min=${throwsNoSuchElement { empty.min() }}")
    println("throws-minBy=${throwsNoSuchElement { empty.minBy { it.code } }}")
    println("throws-minOf=${throwsNoSuchElement { empty.minOf { it.code } }}")
    println("throws-minOfWith=${throwsNoSuchElement { empty.minOfWith(Comparator<Int> { a, b -> a.compareTo(b) }) { it.code } }}")
    println("throws-minWith=${throwsNoSuchElement { empty.minWith(Comparator<Char> { a, b -> a.compareTo(b) }) }}")

    var selectorCalls = 0
    println("singleton-minBy=${"z".minBy { selectorCalls += 1; it }}")
    println("singleton-selectorCalls=$selectorCalls")
}
