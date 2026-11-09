package java.util.zip

/** A streaming zlib encoder that emits valid stored DEFLATE blocks. */
public class Deflater public constructor(
    private var level: Int,
    private val nowrap: Boolean,
) {
    private var strategy = DEFAULT_STRATEGY
    private var input = byteArrayOf()
    private var inputOffset = 0
    private var pending = byteArrayOf()
    private var pendingOffset = 0
    private var finishRequested = false
    private var finalBlockCreated = false
    private var finishedFlag = false
    private var ended = false
    private var bytesRead = 0L
    private var bytesWritten = 0L
    private val checksum = Adler32()

    init {
        validateLevel(level)
        if (!nowrap) pending = byteArrayOf(0x78, if (level == BEST_COMPRESSION) 0xDA.toByte() else 0x9C.toByte())
    }

    public constructor() : this(DEFAULT_COMPRESSION, false)
    public constructor(level: Int) : this(level, false)

    public fun setInput(input: ByteArray) = setInput(input, 0, input.size)

    public fun setInput(input: ByteArray, offset: Int, length: Int) {
        ensureOpen()
        if (finishRequested) throw IllegalStateException("finish() has already been called")
        validateRange(input.size, offset, length)
        if (!needsInput()) throw IllegalStateException("Previous input has not been consumed")
        this.input = ByteArray(length)
        var index = 0
        while (index < length) {
            this.input[index] = input[offset + index]
            index++
        }
        inputOffset = 0
    }

    public fun needsInput(): Boolean = inputOffset >= input.size

    public fun finish() {
        ensureOpen()
        finishRequested = true
    }

    public fun finished(): Boolean = finishedFlag

    public fun deflate(output: ByteArray): Int = deflate(output, 0, output.size, NO_FLUSH)

    public fun deflate(output: ByteArray, offset: Int, length: Int): Int =
        deflate(output, offset, length, NO_FLUSH)

    public fun deflate(output: ByteArray, offset: Int, length: Int, flush: Int): Int {
        ensureOpen()
        validateRange(output.size, offset, length)
        if (length == 0 || finishedFlag) return 0
        if (pendingOffset >= pending.size) {
            pending = byteArrayOf()
            pendingOffset = 0
            when {
                !needsInput() -> prepareDataBlock()
                finishRequested && !finalBlockCreated -> prepareFinalBlock()
                else -> return 0
            }
        }
        val count = minOf(length, pending.size - pendingOffset)
        var index = 0
        while (index < count) {
            output[offset + index] = pending[pendingOffset + index]
            index++
        }
        pendingOffset += count
        bytesWritten += count.toLong()
        if (pendingOffset >= pending.size && finalBlockCreated) finishedFlag = true
        return count
    }

    private fun prepareDataBlock() {
        val count = minOf(MAX_BLOCK_SIZE, input.size - inputOffset)
        pending = ByteArray(count + 5)
        pending[0] = 0
        writeUInt16(count, pending, 1)
        writeUInt16(count xor 0xFFFF, pending, 3)
        var index = 0
        while (index < count) {
            val value = input[inputOffset + index]
            pending[index + 5] = value
            checksum.update(value.toInt())
            index++
        }
        inputOffset += count
        bytesRead += count.toLong()
        pendingOffset = 0
    }

    private fun prepareFinalBlock() {
        val trailerSize = if (nowrap) 0 else 4
        pending = ByteArray(5 + trailerSize)
        pending[0] = 1
        writeUInt16(0, pending, 1)
        writeUInt16(0xFFFF, pending, 3)
        if (!nowrap) {
            val value = checksum.value.toInt()
            pending[5] = (value ushr 24).toByte()
            pending[6] = (value ushr 16).toByte()
            pending[7] = (value ushr 8).toByte()
            pending[8] = value.toByte()
        }
        pendingOffset = 0
        finalBlockCreated = true
    }

    public fun getBytesRead(): Long = bytesRead
    public fun getBytesWritten(): Long = bytesWritten
    public fun getAdler(): Long = checksum.value

    public fun reset() {
        ensureOpen()
        input = byteArrayOf()
        inputOffset = 0
        pending = if (nowrap) byteArrayOf() else byteArrayOf(0x78, if (level == BEST_COMPRESSION) 0xDA.toByte() else 0x9C.toByte())
        pendingOffset = 0
        finishRequested = false
        finalBlockCreated = false
        finishedFlag = false
        bytesRead = 0L
        bytesWritten = 0L
        checksum.reset()
    }

    public fun end() {
        ended = true
        input = byteArrayOf()
        pending = byteArrayOf()
    }

    public fun setLevel(level: Int) {
        ensureOpen()
        validateLevel(level)
        this.level = level
    }

    public fun setStrategy(strategy: Int) {
        ensureOpen()
        if (strategy !in DEFAULT_STRATEGY..HUFFMAN_ONLY) throw IllegalArgumentException("Invalid strategy")
        this.strategy = strategy
    }

    public fun setDictionary(dictionary: ByteArray) = setDictionary(dictionary, 0, dictionary.size)

    public fun setDictionary(dictionary: ByteArray, offset: Int, length: Int) {
        ensureOpen()
        validateRange(dictionary.size, offset, length)
        if (length != 0) throw IllegalArgumentException("Preset dictionaries are not supported")
    }

    private fun ensureOpen() {
        if (ended) throw IllegalStateException("Deflater has been closed")
    }

    private fun validateRange(size: Int, offset: Int, length: Int) {
        if (offset < 0 || length < 0 || offset > size - length) throw IndexOutOfBoundsException()
    }

    private fun writeUInt16(value: Int, target: ByteArray, offset: Int) {
        target[offset] = value.toByte()
        target[offset + 1] = (value ushr 8).toByte()
    }

    public companion object {
        public const val DEFAULT_COMPRESSION: Int = -1
        public const val NO_COMPRESSION: Int = 0
        public const val BEST_SPEED: Int = 1
        public const val BEST_COMPRESSION: Int = 9
        public const val DEFAULT_STRATEGY: Int = 0
        public const val FILTERED: Int = 1
        public const val HUFFMAN_ONLY: Int = 2
        public const val NO_FLUSH: Int = 0
        public const val SYNC_FLUSH: Int = 2
        public const val FULL_FLUSH: Int = 3
        public const val FINISH: Int = 4
        private const val MAX_BLOCK_SIZE: Int = 65_535

        private fun validateLevel(level: Int) {
            if (level != DEFAULT_COMPRESSION && level !in NO_COMPRESSION..BEST_COMPRESSION) {
                throw IllegalArgumentException("Invalid compression level")
            }
        }
    }
}
