// KUU-641: StringBuilder.reverse() keeps surrogate pairs, and insertRange
// accepts a StringBuilder CharSequence without ClassCastException.
fun main() {
    val paired = StringBuilder("a\uD800\uDC00b")
    paired.reverse()
    dumpUnits(paired.toString())

    val unpaired = StringBuilder("\uDC00\uD800")
    unpaired.reverse()
    dumpUnits(unpaired.toString())

    println(StringBuilder("abc").reverse().toString())

    val dst = StringBuilder("abc")
    val src = StringBuilder("XYZ")
    dst.insertRange(1, src, 0, 2)
    println(dst.toString())
}

private fun dumpUnits(value: String) {
    var index = 0
    while (index < value.length) {
        if (index > 0) print(",")
        print(value[index].code)
        index += 1
    }
    println()
}
