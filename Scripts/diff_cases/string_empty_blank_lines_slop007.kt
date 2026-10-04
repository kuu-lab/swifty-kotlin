fun escape(value: String): String {
    return value
        .replace("\r", "<CR>")
        .replace("\n", "<LF>")
        .replace("\t", "<TAB>")
}

fun formatLines(values: List<String>): String {
    return values.map { escape(it) }.joinToString("|", "[", "]")
}

fun probe(label: String, value: CharSequence) {
    val emptyResult = value.ifEmpty { "<empty>" }
    val blankResult = value.ifBlank { "<blank>" }
    println(
        label +
            ":isEmpty=" + value.isEmpty() +
            ",isBlank=" + value.isBlank() +
            ",ifEmpty=" + escape(emptyResult.toString()) +
            ",ifBlank=" + escape(blankResult.toString()) +
            ",lines=" + formatLines(value.lines()) +
            ",sequence=" + formatLines(value.lineSequence().toList())
    )
}

fun main() {
    probe("string-empty", "")
    probe("string-lf", "a\nb")
    probe("string-crlf", "a\r\nb")
    probe("string-cr", "a\rb")
    probe("charsequence-empty", StringBuilder(""))
    probe("charsequence-blank", StringBuilder(" \t\r\n"))
    probe("charsequence-crlf", StringBuilder("a\r\nb"))
    probe("charsequence-cr", StringBuilder("a\rb"))
}
