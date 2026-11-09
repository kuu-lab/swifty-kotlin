// DIFF_JVM
// KUU-4319: Regex must match isolated UTF-16 surrogate code units the way
// java.util.regex does, and match results/replacements must round-trip them
// instead of collapsing to U+FFFD.
fun main() {
    val hi = "\uD800"
    val lo = "\uDC00"
    val mixed = "a\uD800b"

    // Property matches on isolated surrogates.
    println(Regex("\\p{Cs}").containsMatchIn(hi))
    println(Regex("\\p{Cs}").containsMatchIn(lo))
    println(Regex("\\p{C}").containsMatchIn(hi))
    println(Regex("[\\uD800-\\uDFFF]").containsMatchIn(lo))
    println(Regex("\\p{Cs}").containsMatchIn(mixed))
    // A well-formed pair is one supplementary scalar, not Cs.
    println(Regex("\\p{Cs}").containsMatchIn("\uD800\uDC00"))
    println(Regex("\\p{IsCOMMON}").containsMatchIn(hi))
    println(Regex("\\p{InHigh Surrogates}").containsMatchIn(hi))
    println(Regex("\\p{InHigh Surrogates}").containsMatchIn(lo))
    println(Regex("\\p{InLow Surrogates}").containsMatchIn(lo))

    // Match results keep UTF-16 offsets; group values round-trip.
    val m = Regex("(a)?(\\p{Cs})").find("xa\uD800b")!!
    println(m.value.length)
    println(m.groupValues[2].length)
    println(m.groupValues[1])
    println(m.range.first)
    println(m.range.last)

    // findAll / replace / replaceFirst / split / matchEntire.
    println(Regex("\\p{Cs}").findAll("a\uD800b\uDC00c").count())
    println("a\uD800b".replace(Regex("\\p{Cs}"), "X").length)
    println("a\uD800b".replaceFirst(Regex("\\p{Cs}"), "X").length)
    println("a\uD800b".split(Regex("\\p{Cs}")).size)
    println(Regex("\\p{Cs}").matchEntire(lo) != null)

    val seq = Regex("\\p{Cs}").findAll("x\uD800y\uDC00").toList()
    println(seq.size)
    println(seq[0].range.first)
    println(seq[1].range.first)
}
