package java.nio

/** A position-based view of an integer array. */
public class IntBuffer private constructor(
    private val ints: IntArray,
    private val start: Int,
    private val extent: Int,
    private val readOnly: Boolean,
) : Buffer() {
    private var currentPosition: Int = 0
    private var currentLimit: Int = extent
    private var currentMark: Int = -1

    public override fun capacity(): Int = extent
    public override fun position(): Int = currentPosition
    public override fun position(newPosition: Int): IntBuffer {
        require(newPosition >= 0 && newPosition <= currentLimit)
        if (currentMark > newPosition) currentMark = -1
        currentPosition = newPosition
        return this
    }
    public override fun limit(): Int = currentLimit
    public override fun limit(newLimit: Int): IntBuffer {
        require(newLimit >= 0 && newLimit <= extent)
        if (currentPosition > newLimit) currentPosition = newLimit
        if (currentMark > newLimit) currentMark = -1
        currentLimit = newLimit
        return this
    }
    public override fun mark(): IntBuffer { currentMark = currentPosition; return this }
    public override fun reset(): IntBuffer {
        if (currentMark < 0) throw InvalidMarkException()
        currentPosition = currentMark
        return this
    }
    public override fun clear(): IntBuffer { currentPosition = 0; currentLimit = extent; currentMark = -1; return this }
    public override fun flip(): IntBuffer { currentLimit = currentPosition; currentPosition = 0; currentMark = -1; return this }
    public override fun rewind(): IntBuffer { currentPosition = 0; currentMark = -1; return this }
    public override fun remaining(): Int = currentLimit - currentPosition
    public override fun hasRemaining(): Boolean = currentPosition < currentLimit
    public override fun isReadOnly(): Boolean = readOnly
    public override fun isDirect(): Boolean = false
    @get:kotlin.jvm.JvmName("isReadOnly")
    public val isReadOnly: Boolean get() = isReadOnly()
    @get:kotlin.jvm.JvmName("isDirect")
    public val isDirect: Boolean get() = isDirect()
    public override fun hasArray(): Boolean = !readOnly
    public override fun array(): IntArray {
        if (readOnly) throw ReadOnlyBufferException()
        return ints
    }
    public override fun arrayOffset(): Int {
        array()
        return start
    }

    public operator fun get(): Int {
        if (!hasRemaining()) throw BufferUnderflowException()
        return ints[start + currentPosition++]
    }

    public operator fun get(index: Int): Int {
        if (index < 0 || index >= currentLimit) throw IndexOutOfBoundsException()
        return ints[start + index]
    }

    public fun put(value: Int): IntBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (!hasRemaining()) throw BufferOverflowException()
        ints[start + currentPosition++] = value
        return this
    }

    public fun put(index: Int, value: Int): IntBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (index < 0 || index >= currentLimit) throw IndexOutOfBoundsException()
        ints[start + index] = value
        return this
    }

    public fun put(source: IntArray): IntBuffer = put(source, 0, source.size)

    public fun put(source: IntArray, offset: Int, length: Int): IntBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (offset < 0 || length < 0 || offset > source.size - length) throw IndexOutOfBoundsException()
        if (length > remaining()) throw BufferOverflowException()
        val copy = source.copyOfRange(offset, offset + length)
        for (index in 0..<length) ints[start + currentPosition + index] = copy[index]
        currentPosition += length
        return this
    }

    public fun put(source: IntBuffer): IntBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (source === this) throw IllegalArgumentException("Source buffer is this buffer")
        if (source.remaining() > remaining()) throw BufferOverflowException()
        val count = source.remaining()
        val copy = IntArray(count)
        for (index in 0..<count) copy[index] = source.get()
        return put(copy)
    }

    public fun slice(): IntBuffer = IntBuffer(ints, start + currentPosition, remaining(), readOnly)

    public fun duplicate(): IntBuffer {
        val result = IntBuffer(ints, start, extent, readOnly)
        result.currentPosition = currentPosition
        result.currentLimit = currentLimit
        result.currentMark = currentMark
        return result
    }

    public fun asReadOnlyBuffer(): IntBuffer {
        val result = IntBuffer(ints, start, extent, true)
        result.currentPosition = currentPosition
        result.currentLimit = currentLimit
        result.currentMark = currentMark
        return result
    }

    override fun toString(): String = "java.nio.HeapIntBuffer[pos=" + currentPosition +
        " lim=" + currentLimit + " cap=" + extent + "]"

    public companion object {
        public fun allocate(capacity: Int): IntBuffer {
            require(capacity >= 0) { "Negative capacity" }
            return IntBuffer(IntArray(capacity), 0, capacity, false)
        }

        public fun wrap(array: IntArray): IntBuffer = IntBuffer(array, 0, array.size, false)

        public fun wrap(array: IntArray, offset: Int, length: Int): IntBuffer {
            if (offset < 0 || length < 0 || offset > array.size - length) throw IndexOutOfBoundsException()
            val result = wrap(array)
            result.currentPosition = offset
            result.currentLimit = offset + length
            return result
        }
    }
}
