package java.nio

import kotlin.fromBits

/** Views share storage; position, limit and mark belong to each view.
 * This is not a JVM classfile. */
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
    private var currentOrder: ByteOrder = ByteOrder.BIG_ENDIAN

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
    public fun order(): ByteOrder = currentOrder
    public fun order(order: ByteOrder): ByteBuffer { currentOrder = order; return this }

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
    public fun getChar(): Char = Char(getShort().toUShort())
    public fun getChar(index: Int): Char = Char(getShort(index).toUShort())
    public fun getShort(): Short = getBits(2).toShort()
    public fun getShort(index: Int): Short = getBits(index, 2).toShort()
    public fun getInt(): Int = getBits(4).toInt()
    public fun getInt(index: Int): Int = getBits(index, 4).toInt()
    public fun getLong(): Long = getBits(8)
    public fun getLong(index: Int): Long = getBits(index, 8)
    public fun getFloat(): Float = fromBits(getInt())
    public fun getFloat(index: Int): Float = fromBits(getInt(index))
    public fun getDouble(): Double = fromBits(getLong())
    public fun getDouble(index: Int): Double = fromBits(getLong(index))
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
    public fun putChar(value: Char): ByteBuffer = putBits(value.code.toLong(), 2)
    public fun putChar(index: Int, value: Char): ByteBuffer = putBits(index, value.code.toLong(), 2)
    public fun putShort(value: Short): ByteBuffer = putBits(value.toLong(), 2)
    public fun putShort(index: Int, value: Short): ByteBuffer = putBits(index, value.toLong(), 2)
    public fun putInt(value: Int): ByteBuffer = putBits(value.toLong(), 4)
    public fun putInt(index: Int, value: Int): ByteBuffer = putBits(index, value.toLong(), 4)
    public fun putLong(value: Long): ByteBuffer = putBits(value, 8)
    public fun putLong(index: Int, value: Long): ByteBuffer = putBits(index, value, 8)
    public fun putFloat(value: Float): ByteBuffer = putBits(value.toRawBits().toLong(), 4)
    public fun putFloat(index: Int, value: Float): ByteBuffer = putBits(index, value.toRawBits().toLong(), 4)
    public fun putDouble(value: Double): ByteBuffer = putBits(value.toRawBits(), 8)
    public fun putDouble(index: Int, value: Double): ByteBuffer = putBits(index, value.toRawBits(), 8)
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

    private fun getBits(width: Int): Long {
        if (width > remaining()) throw BufferUnderflowException()
        val value = getBits(currentPosition, width)
        currentPosition += width
        return value
    }

    private fun getBits(index: Int, width: Int): Long {
        if (index < 0 || index > currentLimit - width) throw IndexOutOfBoundsException()
        var value = 0L
        for (offset in 0..<width) {
            val byteIndex = if (currentOrder == ByteOrder.BIG_ENDIAN) width - offset - 1 else offset
            val shift = byteIndex * 8
            val byteValue = bytes[start + index + offset].toInt() and 0xff
            value = value or (byteValue.toLong() shl shift)
        }
        return value
    }

    private fun putBits(value: Long, width: Int): ByteBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (width > remaining()) throw BufferOverflowException()
        putBitsAt(currentPosition, value, width)
        currentPosition += width
        return this
    }

    private fun putBits(index: Int, value: Long, width: Int): ByteBuffer {
        if (readOnly) throw ReadOnlyBufferException()
        if (index < 0 || index > currentLimit - width) throw IndexOutOfBoundsException()
        putBitsAt(index, value, width)
        return this
    }

    private fun putBitsAt(index: Int, value: Long, width: Int) {
        for (offset in 0..<width) {
            val byteIndex = if (currentOrder == ByteOrder.BIG_ENDIAN) width - offset - 1 else offset
            val shift = byteIndex * 8
            bytes[start + index + offset] = (value ushr shift).toByte()
        }
    }
}
