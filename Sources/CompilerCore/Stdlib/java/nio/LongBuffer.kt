package java.nio

/** A position-based view of a long array. */
public class LongBuffer private constructor(
    private val longs: LongArray,
    private val start: Int,
    private val extent: Int,
    private val readOnly: Boolean,
) : Buffer() {
    private var currentPosition: Int = 0
    private var currentLimit: Int = extent
    private var currentMark: Int = -1

    public override fun capacity(): Int = extent
    public override fun position(): Int = currentPosition
    public override fun position(newPosition: Int): LongBuffer {
        require(newPosition >= 0 && newPosition <= currentLimit)
        if (currentMark > newPosition) currentMark = -1
        currentPosition = newPosition
        return this
    }
    public override fun limit(): Int = currentLimit
    public override fun limit(newLimit: Int): LongBuffer {
        require(newLimit >= 0 && newLimit <= extent)
        if (currentPosition > newLimit) currentPosition = newLimit
        if (currentMark > newLimit) currentMark = -1
        currentLimit = newLimit
        return this
    }
    public override fun mark(): LongBuffer { currentMark = currentPosition; return this }
    public override fun reset(): LongBuffer {
        if (currentMark < 0) throw InvalidMarkException()
        currentPosition = currentMark
        return this
    }
    public override fun clear(): LongBuffer { currentPosition = 0; currentLimit = extent; currentMark = -1; return this }
    public override fun flip(): LongBuffer { currentLimit = currentPosition; currentPosition = 0; currentMark = -1; return this }
    public override fun rewind(): LongBuffer { currentPosition = 0; currentMark = -1; return this }
    public override fun remaining(): Int = currentLimit - currentPosition
    public override fun hasRemaining(): Boolean = currentPosition < currentLimit
    public override fun isReadOnly(): Boolean = readOnly
    public override fun isDirect(): Boolean = false
    @get:kotlin.jvm.JvmName("isReadOnly")
    public val isReadOnly: Boolean get() = isReadOnly()
    @get:kotlin.jvm.JvmName("isDirect")
    public val isDirect: Boolean get() = isDirect()
    public override fun hasArray(): Boolean = !readOnly
    public override fun array(): LongArray {
        if (readOnly) throw ReadOnlyBufferException()
        return longs
    }
    public override fun arrayOffset(): Int {
        array()
        return start
    }

    public operator fun get(): Long {
        if (!hasRemaining()) throw BufferUnderflowException()
        return longs[start + currentPosition++]
    }

    public operator fun get(index: Int): Long {
        if (index < 0 || index >= currentLimit) throw IndexOutOfBoundsException()
        return longs[start + index]
    }

    public fun put(value: Long): LongBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (!hasRemaining()) throw BufferOverflowException()
        longs[start + currentPosition++] = value
        return this
    }

    public fun put(index: Int, value: Long): LongBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (index < 0 || index >= currentLimit) throw IndexOutOfBoundsException()
        longs[start + index] = value
        return this
    }

    public fun put(source: LongArray): LongBuffer = put(source, 0, source.size)

    public fun put(source: LongArray, offset: Int, length: Int): LongBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (offset < 0 || length < 0 || offset > source.size - length) throw IndexOutOfBoundsException()
        if (length > remaining()) throw BufferOverflowException()
        val copy = source.copyOfRange(offset, offset + length)
        for (index in 0..<length) longs[start + currentPosition + index] = copy[index]
        currentPosition += length
        return this
    }

    public fun put(source: LongBuffer): LongBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (source === this) throw IllegalArgumentException("Source buffer is this buffer")
        if (source.remaining() > remaining()) throw BufferOverflowException()
        val count = source.remaining()
        val copy = LongArray(count)
        for (index in 0..<count) copy[index] = source.get()
        return put(copy)
    }

    public fun slice(): LongBuffer = LongBuffer(longs, start + currentPosition, remaining(), readOnly)

    public fun duplicate(): LongBuffer {
        val result = LongBuffer(longs, start, extent, readOnly)
        result.currentPosition = currentPosition
        result.currentLimit = currentLimit
        result.currentMark = currentMark
        return result
    }

    public fun asReadOnlyBuffer(): LongBuffer {
        val result = LongBuffer(longs, start, extent, true)
        result.currentPosition = currentPosition
        result.currentLimit = currentLimit
        result.currentMark = currentMark
        return result
    }

    override fun toString(): String = "java.nio.HeapLongBuffer[pos=" + currentPosition +
        " lim=" + currentLimit + " cap=" + extent + "]"

    public companion object {
        public fun allocate(capacity: Int): LongBuffer {
            require(capacity >= 0) { "Negative capacity" }
            return LongBuffer(LongArray(capacity), 0, capacity, false)
        }

        public fun wrap(array: LongArray): LongBuffer = LongBuffer(array, 0, array.size, false)

        public fun wrap(array: LongArray, offset: Int, length: Int): LongBuffer {
            if (offset < 0 || length < 0 || offset > array.size - length) throw IndexOutOfBoundsException()
            val result = wrap(array)
            result.currentPosition = offset
            result.currentLimit = offset + length
            return result
        }
    }
}
