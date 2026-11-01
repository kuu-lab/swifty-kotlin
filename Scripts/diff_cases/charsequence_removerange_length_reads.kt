// CharSequence.removeRange must read a custom receiver's `length` exactly as
// often as the JVM: once for the StringBuilder capacity, once per appended
// range check, and once for the final append bound — the stdlib's own bounds
// checks must not add reads.
class CountingSequence(private val content: String) : CharSequence {
    var lengthReads = 0
    override val length: Int
        get() {
            lengthReads += 1
            return content.length
        }
    override fun get(index: Int): Char = content[index]
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        content.substring(startIndex, endIndex)
    override fun toString(): String = content
}

fun main() {
    val middle = CountingSequence("abcdef")
    println(middle.removeRange(1, 3))
    println(middle.lengthReads)

    val prefix = CountingSequence("abcdef")
    println(prefix.removeRange(0, 2))
    println(prefix.lengthReads)

    val suffix = CountingSequence("abcdef")
    println(suffix.removeRange(4..5))
    println(suffix.lengthReads)

    val outOfBounds = CountingSequence("abc")
    try {
        outOfBounds.removeRange(1, 5)
        println("no-throw")
    } catch (e: IndexOutOfBoundsException) {
        println("index")
    }
}
