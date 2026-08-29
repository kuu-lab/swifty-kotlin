import kotlin.text.RegexOption

fun main() {
    val entries = RegexOption.entries
    println(entries.size)
    println(entries[0] === RegexOption.IGNORE_CASE)
    println(entries[1] === RegexOption.MULTILINE)
    println(entries[2] === RegexOption.LITERAL)
    println(entries[3] === RegexOption.UNIX_LINES)
    println(entries[4] === RegexOption.COMMENTS)
    println(entries[5] === RegexOption.DOT_MATCHES_ALL)
    println(entries[6] === RegexOption.CANON_EQ)

    val values = RegexOption.values()
    println(values[5] === RegexOption.DOT_MATCHES_ALL)
    println(RegexOption.valueOf("CANON_EQ") === RegexOption.CANON_EQ)

    try {
        RegexOption.valueOf("missing")
        println("no-throw")
    } catch (e: IllegalArgumentException) {
        println("IllegalArgumentException")
    }
}
