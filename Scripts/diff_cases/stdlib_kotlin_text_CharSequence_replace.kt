private class RecordedSequence(private val content: String) : CharSequence {
    override val length: Int
        get() = content.length

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        RecordedSequence(content.substring(startIndex, endIndex))

    override fun toString(): String = "wrong-toString"
}

private class ReplacementSequence(private val content: String) : CharSequence {
    override val length: Int
        get() = content.length

    override fun get(index: Int): Char = content[index]

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.substring(startIndex, endIndex)

    override fun toString(): String = "wrong-replacement"
}

fun main() {
    val source: CharSequence = "a😀aa"
    println(source.replace(Regex("a+"), "X"))
    println(source.replace(Regex("a+")) { match -> "[${match.value}]" })
    println(source.replaceFirst(Regex("a+"), "X"))
    println(source.replaceRange(1, 3, "XY"))
    println(source.replaceRange(1..2, "Z"))
    println(source.replaceRange(1, 1, "Q"))

    val custom: CharSequence = RecordedSequence("a😀aa")
    println(custom.replace(Regex("a+"), "X"))
    println(custom.replace(Regex("a")) { ReplacementSequence("R") })
    println(custom.replaceFirst(Regex("a+"), "Y"))
    println(custom.replaceRange(1, 3, ReplacementSequence("UV")))
    println(custom.replaceRange(1..2, ReplacementSequence("W")))
    fun attempt(label: String, action: () -> CharSequence) {
        try {
            println("$label:ok:${action()}")
        } catch (e: IndexOutOfBoundsException) {
            println("$label:index")
        }
    }

    attempt("negative", { source.replaceRange(-1, 0, "X") })
    attempt("end", { source.replaceRange(0, 6, "X") })
    attempt("reversed", { source.replaceRange(3, 2, "X") })
    attempt("range-negative", { source.replaceRange(-1..-1, "X") })
    attempt("range-max", { source.replaceRange(Int.MAX_VALUE..Int.MAX_VALUE, "X") })
}
