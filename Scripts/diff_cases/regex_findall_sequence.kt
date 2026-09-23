fun main() {
    val r = Regex("b")

    // KUU-770: findAll must return Sequence<MatchResult>, not List.
    val s: Sequence<MatchResult> = r.findAll("abcb")
    println(s.map { it.range.first }.toList())
    println(r.findAll("abcb").map { it.range.first }.toList())

    // The returned sequence is re-iterable.
    val seq = r.findAll("abcb")
    println(seq.count())
    println(seq.count())

    // findAll(input, startIndex) only reports matches at/after the index.
    println(Regex("b").findAll("abcb", 2).toList().size)
    println(Regex("b").findAll("abcb", 4).toList().size)

    // Zero-width patterns stay productive: first() short-circuits lazily.
    println(Regex("").findAll("ab").first().range)
    println(Regex("").findAll("ab").count())

    // replace(input, transform) accepts transforms returning CharSequence,
    // not only String.
    println(r.replace("abcb") { m -> m.value as CharSequence })
    println(r.replace("abcb") { m -> StringBuilder().append("<").append(m.value).append(">") })
    println(r.replace("abcb") { "X" })

    // find(input, startIndex) / matchAt / matchesAt
    println(r.find("abcb", 2)?.range)
    println(r.matchAt("abcb", 1)?.range)
    println(r.matchAt("abcb", 0)?.range)
    println(r.matchesAt("abcb", 1))
    println(r.matchesAt("abcb", 0))

    // CharSequence input overloads (StringBuilder is not a String).
    val cs: CharSequence = StringBuilder("abcb")
    println(r.findAll(cs).count())
    println(r.find(cs)?.range)
    println(r.replace(cs) { m -> m.value as CharSequence })
}
