import java.util.function.IntUnaryOperator
import java.util.function.ToLongFunction
import java.util.stream.IntStream

private fun values(stream: IntStream): String = stream.toArray().joinToString(",")

private class MutableSequence : CharSequence {
    private val contents = StringBuilder("A")
    override val length: Int get() = contents.length
    override fun get(index: Int): Char = contents[index]
    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        contents.subSequence(startIndex, endIndex)
    fun append(value: String) { contents.append(value) }
}

fun main() {
    val text: CharSequence = "A\uD83D\uDE00B"
    println("chars=" + values(text.chars()))
    println("points=" + values(text.codePoints()))
    println("empty=" + values("".codePoints()))
    val unpaired: CharSequence = StringBuilder().append(charArrayOf('X', '\uD800', 'Y', '\uDC00'))
    println("unpaired=" + values(unpaired.codePoints()))

    val mutable = StringBuilder("A")
    val mapped = mutable.chars().map(IntUnaryOperator { it + 1 })
    mutable.append("B")
    println("late-map=" + mapped.sum())
    val boxedBuilder = StringBuilder("A")
    val boxed = boxedBuilder.codePoints().boxed()
    boxedBuilder.append("B")
    println("late-boxed=" + boxed.count())
    val custom = MutableSequence()
    val customStream = (custom as CharSequence).codePoints()
    custom.append("B")
    println("late-custom=" + customStream.sum())

    var calls = 0
    val short = "ABC".chars().map(IntUnaryOperator { calls++; it })
    println("calls-before=$calls")
    println("first=" + short.findFirst().getAsInt())
    println("calls-after=$calls")

    val converted = StringBuilder("A")
    val longs = converted.chars().boxed().mapToLong(ToLongFunction<Int> { (it + 1).toLong() })
    converted.append("B")
    println("late-long=" + longs.sum())
    val once = "A".chars()
    println("once=" + once.count())
    try { once.count(); println("reuse=accepted") } catch (e: IllegalStateException) { println("reuse=rejected") }
}
