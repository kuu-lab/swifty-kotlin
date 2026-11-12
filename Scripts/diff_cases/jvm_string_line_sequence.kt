// DIFF_JVM
import kotlin.sequences.Sequence

private class TrackingCharSequence(private val value: String) : CharSequence {
    var characterReads = 0

    override val length: Int get() = value.length

    override operator fun get(index: Int): Char {
        characterReads++
        return value[index]
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
        value.subSequence(startIndex, endIndex)
}

fun lineSequenceForJava(value: String): Sequence<String> = value.lineSequence()

fun main() {
    println("basic:" + "a\nb".lineSequence().count())
    println("lf:" + "a\nb".lineSequence().toList())
    println("crlf:" + "a\r\nb".lineSequence().toList())
    println("trailing:" + "a\nb\n".lineSequence().toList())
    println("empty-count:" + "".lineSequence().count())
    println("empty-first:<" + "".lineSequence().first() + ">")
    println("cr:" + "a\rb".lineSequence().toList())

    val charSequence: CharSequence = "one\ntwo"
    println("char-sequence:" + charSequence.lineSequence().toList())

    val sequence = "first\nsecond\nthird".lineSequence()
    println("lazy-first:" + sequence.first())
    println("lazy-take:" + sequence.take(2).toList())
    println("lazy-repeat:" + sequence.toList())

    val tracked = TrackingCharSequence("first\nsecond")
    val trackedLines = tracked.lineSequence()
    println("lazy-before:" + tracked.characterReads)
    println("lazy-tracked-first:" + trackedLines.first())
    println("lazy-after-first:" + tracked.characterReads)
}
