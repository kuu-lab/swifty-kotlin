package java.nio

/** A position-based view of a character array. */
public class CharBuffer private constructor(
    private val chars: CharArray,
    private val start: Int,
    private val extent: Int,
    private val readOnly: Boolean,
) : Buffer(), CharSequence {
    private var currentPosition: Int = 0
    private var currentLimit: Int = extent
    private var currentMark: Int = -1

    override val length: Int get() = remaining()

    public override fun capacity(): Int = extent
    public override fun position(): Int = currentPosition
    public override fun position(newPosition: Int): CharBuffer {
        require(newPosition >= 0 && newPosition <= currentLimit)
        if (currentMark > newPosition) currentMark = -1
        currentPosition = newPosition
        return this
    }
    public override fun limit(): Int = currentLimit
    public override fun limit(newLimit: Int): CharBuffer {
        require(newLimit >= 0 && newLimit <= extent)
        if (currentPosition > newLimit) currentPosition = newLimit
        if (currentMark > newLimit) currentMark = -1
        currentLimit = newLimit
        return this
    }
    public override fun mark(): CharBuffer { currentMark = currentPosition; return this }
    public override fun reset(): CharBuffer {
        if (currentMark < 0) throw InvalidMarkException()
        currentPosition = currentMark
        return this
    }
    public override fun clear(): CharBuffer { currentPosition = 0; currentLimit = extent; currentMark = -1; return this }
    public override fun flip(): CharBuffer { currentLimit = currentPosition; currentPosition = 0; currentMark = -1; return this }
    public override fun rewind(): CharBuffer { currentPosition = 0; currentMark = -1; return this }
    public override fun remaining(): Int = currentLimit - currentPosition
    public override fun hasRemaining(): Boolean = currentPosition < currentLimit
    public override fun isReadOnly(): Boolean = readOnly
    public override fun isDirect(): Boolean = false
    @get:kotlin.jvm.JvmName("isReadOnly")
    public val isReadOnly: Boolean get() = isReadOnly()
    @get:kotlin.jvm.JvmName("isDirect")
    public val isDirect: Boolean get() = isDirect()
    public override fun hasArray(): Boolean = !readOnly
    public override fun array(): CharArray {
        if (readOnly) throw ReadOnlyBufferException()
        return chars
    }
    public override fun arrayOffset(): Int {
        array()
        return start
    }

    public operator fun get(): Char {
        if (!hasRemaining()) throw BufferUnderflowException()
        return chars[start + currentPosition++]
    }

    public override operator fun get(index: Int): Char {
        if (index < 0 || index >= currentLimit) throw IndexOutOfBoundsException()
        return chars[start + index]
    }

    public fun put(value: Char): CharBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (!hasRemaining()) throw BufferOverflowException()
        chars[start + currentPosition++] = value
        return this
    }

    public fun put(index: Int, value: Char): CharBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (index < 0 || index >= currentLimit) throw IndexOutOfBoundsException()
        chars[start + index] = value
        return this
    }

    public fun put(source: CharArray): CharBuffer = put(source, 0, source.size)

    public fun put(source: CharArray, offset: Int, length: Int): CharBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (offset < 0 || length < 0 || offset > source.size - length) throw IndexOutOfBoundsException()
        if (length > remaining()) throw BufferOverflowException()
        val copy = source.copyOfRange(offset, offset + length)
        for (index in 0..<length) chars[start + currentPosition + index] = copy[index]
        currentPosition += length
        return this
    }

    public fun put(source: CharBuffer): CharBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (source === this) throw IllegalArgumentException("Source buffer is this buffer")
        if (source.remaining() > remaining()) throw BufferOverflowException()
        val count = source.remaining()
        val copy = CharArray(count)
        for (index in 0..<count) copy[index] = source.get()
        return put(copy)
    }

    public fun slice(): CharBuffer = CharBuffer(chars, start + currentPosition, remaining(), readOnly)

    public fun duplicate(): CharBuffer {
        val result = CharBuffer(chars, start, extent, readOnly)
        result.currentPosition = currentPosition
        result.currentLimit = currentLimit
        result.currentMark = currentMark
        return result
    }

    public fun asReadOnlyBuffer(): CharBuffer {
        val result = CharBuffer(chars, start, extent, true)
        result.currentPosition = currentPosition
        result.currentLimit = currentLimit
        result.currentMark = currentMark
        return result
    }

    override fun subSequence(startIndex: Int, endIndex: Int): CharSequence {
        if (startIndex < 0 || endIndex < startIndex || endIndex > remaining()) throw IndexOutOfBoundsException()
        return String(chars, start + currentPosition + startIndex, endIndex - startIndex)
    }

    override fun toString(): String = String(chars, start + currentPosition, remaining())

    public companion object {
        public fun allocate(capacity: Int): CharBuffer {
            require(capacity >= 0) { "Negative capacity" }
            return CharBuffer(CharArray(capacity), 0, capacity, false)
        }

        public fun wrap(array: CharArray): CharBuffer = CharBuffer(array, 0, array.size, false)

        public fun wrap(array: CharArray, offset: Int, length: Int): CharBuffer {
            if (offset < 0 || length < 0 || offset > array.size - length) throw IndexOutOfBoundsException()
            val result = wrap(array)
            result.currentPosition = offset
            result.currentLimit = offset + length
            return result
        }
    }
}
