fun show(match: MatchResult?) {
    if (match == null) {
        println("null")
    } else {
        println(match.value + ":" + match.range.first + ":" + match.range.last)
    }
}

fun main() {
    // MatchResult.next() must keep ^ / lookbehind / \b against the original input.
    show(Regex("^.").find("ab")!!.next())
    show(Regex("\\b\\w").find("ab")!!.next())
    show(Regex("(?<=^).").find("ab")!!.next())
    show(Regex("a|(?<=a)b").find("ab")!!.next())
    show(Regex("\\d+").find("a1b22")!!.next())
    show(Regex("b|$").find("ab")!!.next())
    show(Regex("^.").find("ab", 1))
    show(Regex("^.", RegexOption.MULTILINE).find("ab\ncd")!!.next())
}
