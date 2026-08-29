fun main() {
    // KSP-1438: Regex.options must decode every reordered RegexOption ordinal.
    val literal = Regex("a", RegexOption.LITERAL)
    println(literal.options.contains(RegexOption.LITERAL))

    val unixLines = Regex("a", RegexOption.UNIX_LINES)
    println(unixLines.options.contains(RegexOption.UNIX_LINES))

    val comments = Regex("a", RegexOption.COMMENTS)
    println(comments.options.contains(RegexOption.COMMENTS))

    val dotMatchesAll = Regex("a", RegexOption.DOT_MATCHES_ALL)
    println(dotMatchesAll.options.contains(RegexOption.DOT_MATCHES_ALL))

    val combined = Regex(
        "a",
        setOf(
            RegexOption.LITERAL,
            RegexOption.UNIX_LINES,
            RegexOption.COMMENTS,
            RegexOption.DOT_MATCHES_ALL
        )
    )
    println(combined.options.contains(RegexOption.LITERAL))
    println(combined.options.contains(RegexOption.UNIX_LINES))
    println(combined.options.contains(RegexOption.COMMENTS))
    println(combined.options.contains(RegexOption.DOT_MATCHES_ALL))
}
