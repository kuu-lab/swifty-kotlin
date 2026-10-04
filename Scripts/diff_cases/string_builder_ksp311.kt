fun main() {
    val typed = StringBuilder()
    typed.append("A")
        .append('-')
        .append(true)
        .append('-')
        .append(42)
        .append('-')
        .append(1234567890123L)
        .append('-')
        .append(3.5f)
        .append('-')
        .append(4.25)
    println(typed.toString())

    val lines = StringBuilder("first")
    lines.appendLine()
    lines.appendLine("second")
    println(lines.toString())

    println(StringBuilder("ab").appendRange("WXYZ", 1, 3).toString())
    println(StringBuilder("ab").insertRange(1, "WXYZ", 1, 3).toString())
    println(StringBuilder("abcd").setRange(1, 3, "XY").toString())
    println(StringBuilder("abcd").deleteRange(1, 3).toString())
    println(StringBuilder("abc").deleteAt(1).toString())
    println(StringBuilder("abc").reverse().toString())

    val op = StringBuilder("abc")
    op[1] = 'X'
    println(op.toString())

    val strings = StringBuilder()
    strings.append("left", "-", null, "-", "right")
    println(strings.toString())

    val anys = StringBuilder()
    anys.append(1, "-", true, "-", null)
    println(anys.toString())
}
