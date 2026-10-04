// SLOP-007: `CharSequence.isBlank` in the bundled stdlib used an ASCII-only
// private whitespace helper (space/tab/LF/CR), so vertical tab (U+000B), the
// 0x1C-0x1F separators, and NBSP (U+00A0, SPACE_SEPARATOR category) were not
// treated as blank, unlike kotlinc. This case pins the Unicode-aware behavior
// after delegating to Char.isWhitespace() (CharPredicates.kt).

fun main() {
    println("\u000B".isBlank())
    println("\u00A0 ".isBlank())
    println("\u001C".isBlank())
    println(" \t\r\n".isBlank())
    println("".isBlank())
    println("x ".isBlank())
    println("\u000B".isNotBlank())
    val blankOnly: String? = "\u00A0\u000B "
    println(blankOnly.isNullOrBlank())
    val absent: String? = null
    println(absent.isNullOrBlank())
}
