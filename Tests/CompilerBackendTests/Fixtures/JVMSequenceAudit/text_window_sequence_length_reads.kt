class ShrinkingLength(private val text: String) : CharSequence {
    var reads = 0
    override val length: Int
        get() {
            reads++
            return when (reads) {
                1 -> text.length
                2 -> 1
                else -> 0
            }
        }

    override fun get(index: Int): Char = text[index]
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence = text.subSequence(startIndex, endIndex)
}

fun main() {
    val source = ShrinkingLength("abcd")
    val windows = source.windowedSequence(2, 1, true) { it.toString() }
    val iterator = windows.iterator()
    println(iterator.next().length)
    println(source.reads)
}
