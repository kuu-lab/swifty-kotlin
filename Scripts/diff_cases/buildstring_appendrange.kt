fun main() {
    val s = buildString {
        appendRange("Hello, World!", 0, 5)
        append(" ")
        appendRange("Hello, World!", 7, 13)
    }
    println(s)

    // UTF-16 indexing: ASCII strings verify start/end range slicing.
    // (Add separate cases with CJK/surrogate pairs to validate non-BMP indexing.)
    val u = buildString {
        appendRange("ABCDE", 1, 4)
        append("|")
        appendRange("abcdef", 0, 3)
        append("|")
        appendRange("12345", 2, 5)
    }
    println(u)
}
