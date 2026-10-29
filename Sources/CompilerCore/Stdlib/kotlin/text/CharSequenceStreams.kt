package kotlin.text

import java.util.stream.IntStream
import java.util.stream.streamSequence

private class CharSequenceStreamIterator(
    private val source: CharSequence,
    private val combineSurrogates: Boolean
) : Iterator<Int> {
    private val end = source.length
    private var index = 0

    override fun hasNext(): Boolean = index < end

    override fun next(): Int {
        if (!hasNext()) throw NoSuchElementException()
        val first = source[index++]
        if (combineSurrogates && first.isHighSurrogate() && index < end) {
            val second = source[index]
            if (second.isLowSurrogate()) {
                index++
                return ((first.code - 0xD800) shl 10) + (second.code - 0xDC00) + 0x10000
            }
        }
        return first.code
    }
}

public fun CharSequence.chars(): IntStream {
    val source = this
    return IntStream.fromSequence(streamSequence { CharSequenceStreamIterator(source, false) })
}

public fun CharSequence.codePoints(): IntStream {
    val source = this
    return IntStream.fromSequence(streamSequence { CharSequenceStreamIterator(source, true) })
}
