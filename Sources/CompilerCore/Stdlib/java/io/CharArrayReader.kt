package java.io

public class CharArrayReader : Reader {
    private val buffer: CharArray
    private val start: Int
    private val length: Int
    private var pos: Int
    private var markPos: Int
    private var closed: Boolean = false

    public constructor(buffer: CharArray) {
        this.buffer = buffer
        this.start = 0
        this.length = buffer.size
        this.pos = 0
        this.markPos = 0
    }

    public constructor(buffer: CharArray, offset: Int, length: Int) {
        if (offset < 0 || length < 0 || offset > buffer.size - length) {
            throw IndexOutOfBoundsException()
        }
        this.buffer = buffer
        this.start = offset
        this.length = length
        this.pos = offset
        this.markPos = offset
    }

    public fun read(): Int {
        checkOpen()
        if (pos >= start + length) return -1
        return buffer[pos++].code
    }

    public override fun read(buffer: CharArray, offset: Int, length: Int): Int {
        checkOpen()
        if (offset < 0 || length < 0 || offset > buffer.size - length) {
            throw IndexOutOfBoundsException()
        }
        if (length == 0) return 0
        val remaining = start + this.length - pos
        if (remaining <= 0) return -1
        val copied = minOf(length, remaining)
        var i = 0
        while (i < copied) {
            buffer[offset + i] = this.buffer[pos + i]
            i += 1
        }
        pos += copied
        return copied
    }

    public fun ready(): Boolean {
        checkOpen()
        return pos < start + length
    }

    public fun mark(readAheadLimit: Int): Unit {
        checkOpen()
        markPos = pos
    }

    public fun markSupported(): Boolean = true

    public fun reset(): Unit {
        checkOpen()
        pos = markPos
    }

    public fun skip(count: Long): Long {
        checkOpen()
        if (count < 0L) throw IllegalArgumentException()
        val remaining = (start + length - pos).toLong()
        val skipped = if (count > remaining) remaining else count
        pos += skipped.toInt()
        return skipped
    }

    public override fun close(): Unit {
        closed = true
    }

    private fun checkOpen(): Unit {
        if (closed) throw IOException()
    }
}
