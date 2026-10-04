import kotlinx.io.*
import kotlinx.io.bytestring.ByteString

class SearchChunks(private val bytes: ByteArray) : RawSource {
    private var position = 0
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (position == bytes.size) return -1L
        sink.writeByte(bytes[position])
        position += 1
        return 1L
    }
    override fun close() {}
}

fun main() {
    val pattern = ByteString(byteArrayOf(2, 3, 2))
    val empty = ByteString()
    for (chunked in listOf(false, true)) {
        val bytes = byteArrayOf(1, 2, 3, 2, 3, 2, 4)
        val buffer = Buffer()
        buffer.write(bytes)
        val source: Source = if (chunked) SearchChunks(bytes).buffered() else buffer
        try { source.request(-1L) } catch (e: IllegalArgumentException) { println(e.message) }
        println(source.startsWith(1))
        println(source.startsWith(2))
        println(source.indexOf(2))
        println(source.indexOf(2, 2L, 3L))
        println(source.indexOf(2, 2L, 4L))
        println(source.indexOf(9))
        println(source.indexOf(1, 100L))
        println(source.indexOf(1, Long.MAX_VALUE))
        println(source.indexOf(1, 0L, 0L))
        try { source.indexOf(1, -1L) } catch (e: IllegalArgumentException) { println(e.message) }
        try { source.indexOf(1, 3L, 2L) } catch (e: IllegalArgumentException) { println(e.message) }
        try { source.indexOf(1, 0L, -1L) } catch (e: IllegalArgumentException) { println(e.message) }
        println(source.indexOf(pattern))
        println(source.indexOf(pattern, 2L))
        println(source.indexOf(pattern, -10L))
        try { source.indexOf(pattern, Long.MAX_VALUE) } catch (e: IllegalArgumentException) { println(e.message) }
        println(source.indexOf(ByteString(byteArrayOf(2, 4, 5))))
        println(source.indexOf(empty, -1L))
        println(source.indexOf(empty, 3L))
        println(source.indexOf(empty, 100L))
        println(source.readByteString(3))
        println(source.readByteString())
        println(source.startsWith(1))
        println(source.readByteString())
    }
    val buffer = Buffer()
    buffer.write(byteArrayOf(0, 1, 2, 3, 2))
    buffer.skip(1L)
    println(buffer.indexOf(pattern))
    println(buffer.indexOf(empty, -1L))
    println(buffer.indexOf(empty, 100L))
    val prefixAtEof = SearchChunks(byteArrayOf(2, 3)).buffered()
    println(prefixAtEof.indexOf(pattern))
    println(prefixAtEof.readByteArray().joinToString())
    val emptyBeyondEof = SearchChunks(byteArrayOf(7, 8)).buffered()
    println(emptyBeyondEof.indexOf(empty, 100L))
    println(emptyBeyondEof.readByteArray().joinToString())
    val lines = SearchChunks("12\r\n34\n".encodeToByteArray()).buffered()
    println(lines.indexOf(10.toByte()))
    println(lines.readLineStrict())
    println(lines.readDecimalLong())
    println(lines.readLine())
    println(lines.readLine())
}
