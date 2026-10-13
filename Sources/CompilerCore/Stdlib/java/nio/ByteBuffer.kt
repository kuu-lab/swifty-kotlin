package java.nio

/** Native source model for byte-buffer interoperability. Views share storage;
 * position, limit and mark belong to each view. This is not a JVM classfile. */
public class ByteBuffer private constructor(
    private val bytes: ByteArray,
    private val start: Int,
    private val extent: Int,
    private val readOnly: Boolean,
    private val direct: Boolean,
) : Buffer() {
    private var currentPosition: Int = 0
    private var currentLimit: Int = extent
    private var currentMark: Int = -1

    public companion object {
        public fun allocate(capacity: Int): ByteBuffer {
            require(capacity >= 0) { "Negative capacity" }
            return ByteBuffer(ByteArray(capacity), 0, capacity, false, false)
        }
        public fun allocateDirect(capacity: Int): ByteBuffer {
            require(capacity >= 0) { "Negative capacity" }
            return ByteBuffer(ByteArray(capacity), 0, capacity, false, true)
        }
        public fun wrap(array: ByteArray): ByteBuffer = ByteBuffer(array, 0, array.size, false, false)
        public fun wrap(array: ByteArray, offset: Int, length: Int): ByteBuffer {
            if (offset < 0 || length < 0 || offset > array.size - length) throw IndexOutOfBoundsException()
            val buffer = wrap(array)
            buffer.currentPosition = offset
            buffer.currentLimit = offset + length
            return buffer
        }
    }
    public override fun capacity(): Int = extent
    public override fun position(): Int = currentPosition
    public override fun position(newPosition: Int): ByteBuffer {
        require(newPosition >= 0 && newPosition <= currentLimit)
        if (currentMark > newPosition) currentMark = -1
        currentPosition = newPosition
        return this
    }
    public override fun limit(): Int = currentLimit
    public override fun limit(newLimit: Int): ByteBuffer {
        require(newLimit >= 0 && newLimit <= extent)
        if (currentPosition > newLimit) currentPosition = newLimit
        if (currentMark > newLimit) currentMark = -1
        currentLimit = newLimit
        return this
    }
    public override fun remaining(): Int = currentLimit - currentPosition
    public override fun hasRemaining(): Boolean = currentPosition < currentLimit
    public override fun isReadOnly(): Boolean = readOnly
    public override fun isDirect(): Boolean = direct

    // Java bean-property spelling used by unchanged Kotlin consumers.
    // Native accessors preserve the Java names in metadata; no classfile is emitted.
    @get:kotlin.jvm.JvmName("isReadOnly")
    public val isReadOnly: Boolean get() = isReadOnly()
    @get:kotlin.jvm.JvmName("isDirect")
    public val isDirect: Boolean get() = isDirect()
    public override fun hasArray(): Boolean = !readOnly && !direct
    public override fun array(): ByteArray {
        if (direct) throw UnsupportedOperationException()
        if (readOnly) throw ReadOnlyBufferException()
        return bytes
    }
    public override fun arrayOffset(): Int {
        array()
        return start
    }
    public override fun mark(): ByteBuffer { currentMark = currentPosition; return this }
    public override fun reset(): ByteBuffer {
        if (currentMark < 0) throw InvalidMarkException()
        currentPosition = currentMark
        return this
    }
    public override fun clear(): ByteBuffer { currentPosition = 0; currentLimit = extent; currentMark = -1; return this }
    public override fun flip(): ByteBuffer { currentLimit = currentPosition; currentPosition = 0; currentMark = -1; return this }
    public override fun rewind(): ByteBuffer { currentPosition = 0; currentMark = -1; return this }
    public fun slice(): ByteBuffer = ByteBuffer(bytes, start + currentPosition, remaining(), readOnly, direct)
    public fun duplicate(): ByteBuffer {
        val view = ByteBuffer(bytes, start, extent, readOnly, direct)
        view.currentPosition = currentPosition
        view.currentLimit = currentLimit
        view.currentMark = currentMark
        return view
    }
    public fun asReadOnlyBuffer(): ByteBuffer {
        val view = ByteBuffer(bytes, start, extent, true, direct)
        view.currentPosition = currentPosition
        view.currentLimit = currentLimit
        view.currentMark = currentMark
        return view
    }
    public fun get(): Byte {
        if (!hasRemaining()) throw BufferUnderflowException()
        return bytes[start + currentPosition++]
    }
    public operator fun get(index: Int): Byte {
        if (index < 0 || index >= currentLimit) throw IndexOutOfBoundsException()
        return bytes[start + index]
    }
    public operator fun get(destination: ByteArray): ByteBuffer = get(destination, 0, destination.size)
    public operator fun get(destination: ByteArray, offset: Int, length: Int): ByteBuffer {
        if (offset < 0 || length < 0 || offset > destination.size - length) throw IndexOutOfBoundsException()
        if (length > remaining()) throw BufferUnderflowException()
        val copy = ByteArray(length)
        for (index in 0..<length) copy[index] = bytes[start + currentPosition + index]
        for (index in 0..<length) destination[offset + index] = copy[index]
        currentPosition += length
        return this
    }
    public fun put(value: Byte): ByteBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (!hasRemaining()) throw BufferOverflowException()
        bytes[start + currentPosition++] = value
        return this
    }
    public fun put(index: Int, value: Byte): ByteBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (index < 0 || index >= currentLimit) throw IndexOutOfBoundsException()
        bytes[start + index] = value
        return this
    }
    public fun put(source: ByteArray): ByteBuffer = put(source, 0, source.size)
    public fun put(source: ByteArray, offset: Int, length: Int): ByteBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (offset < 0 || length < 0 || offset > source.size - length) throw IndexOutOfBoundsException()
        if (length > remaining()) throw BufferOverflowException()
        // A wrapped array may also be the source. Snapshot overlapping data.
        val copy = ByteArray(length)
        for (index in 0..<length) copy[index] = source[offset + index]
        for (index in 0..<length) bytes[start + currentPosition + index] = copy[index]
        currentPosition += length
        return this
    }
}
