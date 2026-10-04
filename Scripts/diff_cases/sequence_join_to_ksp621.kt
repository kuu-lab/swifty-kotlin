fun main() {
    val seq = sequenceOf(1, 2, 3, 4, 5)

    // joinTo (buffer) standalone: no prior diff case exercised Sequence.joinTo
    // directly, only joinToString.
    val plain = StringBuilder()
    seq.joinTo(plain, "|", "<", ">")
    println(plain)

    val defaulted = StringBuilder()
    sequenceOf("a", "b", "c").joinTo(defaulted)
    println(defaulted)

    val transformed = StringBuilder()
    seq.joinTo(transformed, "|", "<", ">", -1, "...") { (it * 10).toString() }
    println(transformed)

    // limit/truncated: Sequence previously had no such overloads at all.
    println(seq.joinToString("|", "<", ">", 3, "..."))
    println(seq.joinToString("|", "<", ">", 3, "...") { (it * 10).toString() })

    val limitedBuffer = StringBuilder()
    seq.joinTo(limitedBuffer, "|", "<", ">", 3, "...")
    println(limitedBuffer)

    val limitedTransformedBuffer = StringBuilder()
    seq.joinTo(limitedTransformedBuffer, "|", "<", ">", 3, "...") { (it * 10).toString() }
    println(limitedTransformedBuffer)

    // limit greater than the element count must not append the truncated marker.
    println(seq.joinToString("|", "<", ">", 10, "..."))

    // limit = 0 truncates immediately.
    println(seq.joinToString("|", "<", ">", 0, "..."))

    // Laziness: joinToString(limit=...) on an infinite sequence must short-circuit
    // instead of materializing the whole sequence first.
    val infinite = generateSequence(1) { it + 1 }
    println(infinite.joinToString(", ", "", "", 5, "..."))
}
