package java.io

public class StringReader(private val source: String) : Reader {
    private var nextIndex: Int = 0
    private var markIndex: Int = 0
    private var closed: Boolean = false

    public fun read(): Int {
        checkOpen()
        if (nextIndex >= source.length) return -1
        return source[nextIndex++].code
    }

    public override fun read(buffer: CharArray, offset: Int, length: Int): Int {
        checkOpen()
        if (offset < 0 || length < 0 || offset > buffer.size - length) {
            throw IndexOutOfBoundsException()
        }
        if (length == 0) return 0
        if (nextIndex >= source.length) return -1

        var copied = 0
        while (copied < length && nextIndex < source.length) {
            buffer[offset + copied] = source[nextIndex]
            copied += 1
            nextIndex += 1
        }
        return copied
    }

    public fun ready(): Boolean {
        checkOpen()
        return nextIndex < source.length
    }

    public fun mark(readAheadLimit: Int): Unit {
        checkOpen()
        markIndex = nextIndex
    }

    public fun reset(): Unit {
        checkOpen()
        nextIndex = markIndex
    }

    public fun skip(count: Long): Long {
        checkOpen()
        if (count < 0L) throw IllegalArgumentException()
        val remaining = source.length - nextIndex
        val skipped = if (count > remaining.toLong()) remaining else count.toInt()
        nextIndex += skipped
        return skipped.toLong()
    }

    public override fun close(): Unit {
        closed = true
    }

    private fun checkOpen(): Unit {
        if (closed) throw IOException()
    }
}
