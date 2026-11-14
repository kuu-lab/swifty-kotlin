package kotlin.ranges

import kotlin.collections.CharIterator

public open class CharProgression(public val first: Char, last: Char, public val step: Int) :
    Iterable<Char>, kotlin.jvm.internal.markers.KMappedMarker {
    private val integers = IntProgression(first.code, last.code, step)
    public val last: Char = integers.last.toChar()

    public open fun isEmpty(): Boolean = integers.isEmpty()

    override fun iterator(): CharIterator = CharIteratorAdapter(integers.iterator())

    override fun equals(other: Any?): Boolean = other is CharProgression &&
        (isEmpty() && other.isEmpty() || first == other.first && last == other.last && step == other.step)

    override fun hashCode(): Int = if (isEmpty()) -1 else 31 * (31 * first.code + last.code) + step

    override fun toString(): String =
        if (step > 0) "$first..$last step $step" else "$first downTo $last step ${-step}"

    public companion object {
        public fun fromClosedRange(rangeStart: Char, rangeEnd: Char, step: Int): CharProgression =
            CharProgression(rangeStart, rangeEnd, step)
    }
}

private class CharIteratorAdapter(private val integers: kotlin.collections.IntIterator) : CharIterator() {
    override fun hasNext(): Boolean = integers.hasNext()
    override fun nextChar(): Char = integers.nextInt().toChar()
}

public class CharRange(start: Char, endInclusive: Char) : CharProgression(start, endInclusive, 1),
    ClosedRange<Char>, OpenEndRange<Char> {
    override val start: Char get() = first
    override val endInclusive: Char get() = last
    override val endExclusive: Char
        get() {
            if (last == Char.MAX_VALUE) {
                throw IllegalStateException("Cannot return the exclusive upper bound of a range that includes MAX_VALUE.")
            }
            return (last.code + 1).toChar()
        }

    @kotlin.jvm.JvmName("getStart")
    public fun boxedStart(): Char? = start

    @kotlin.jvm.JvmName("getEndInclusive")
    public fun boxedEndInclusive(): Char? = endInclusive

    @kotlin.jvm.JvmName("getEndExclusive")
    public fun boxedEndExclusive(): Char? = endExclusive

    override fun isEmpty(): Boolean = first > last
    override operator fun contains(value: Char): Boolean = value >= first && value <= last
    override fun equals(other: Any?): Boolean = other is CharRange &&
        (isEmpty() && other.isEmpty() || first == other.first && last == other.last)
    override fun hashCode(): Int = if (isEmpty()) -1 else 31 * first.code + last.code
    override fun toString(): String = "$first..$last"

    public companion object {
        public val EMPTY: CharRange = CharRange('\u0001', '\u0000')
    }
}
