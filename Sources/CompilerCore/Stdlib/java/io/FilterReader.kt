package java.io

public open class FilterReader(protected val `in`: Reader) : Reader() {
    public override fun read(buffer: CharArray, offset: Int, length: Int): Int =
        `in`.read(buffer, offset, length)

    public open fun read(): Int {
        val buffer = CharArray(1)
        val count = read(buffer, 0, 1)
        return if (count <= 0) count else buffer[0].code
    }

    public fun skip(count: Long): Long {
        var remaining = count
        var skipped = 0L
        val buffer = CharArray(8192)
        while (remaining > 0L) {
            val chunk = minOf(remaining, buffer.size.toLong()).toInt()
            val n = read(buffer, 0, chunk)
            if (n <= 0) break
            skipped += n
            remaining -= n
        }
        return skipped
    }

    public fun ready(): Boolean = false

    public fun mark(readAheadLimit: Int): Unit {}

    public fun reset(): Unit {
        throw IOException("Stream not marked")
    }

    public fun markSupported(): Boolean = false

    public override fun close(): Unit = `in`.close()
}
