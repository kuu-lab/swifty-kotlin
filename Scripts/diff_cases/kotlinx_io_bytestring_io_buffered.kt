import kotlinx.io.Buffer
import kotlinx.io.RawSink
import kotlinx.io.RawSource
import kotlinx.io.buffered
import kotlinx.io.bytestring.ByteString
import kotlinx.io.indexOf
import kotlinx.io.readByteString
import kotlinx.io.snapshot
import kotlinx.io.write

class ByteStringChunkedSource(private val data: ByteArray) : RawSource {
    private var offset = 0
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (offset == data.size) return -1L
        val count = minOf(byteCount, 3L, (data.size - offset).toLong()).toInt()
        sink.write(data, offset, offset + count)
        offset += count
        return count.toLong()
    }
    override fun close() {}
}

class ByteStringRecordingSink : RawSink {
    val output = Buffer()
    override fun write(source: Buffer, byteCount: Long) { output.write(source, byteCount) }
    override fun flush() {}
    override fun close() {}
}

fun main() {
    val source = ByteStringChunkedSource(byteArrayOf(1, 2, 3, 4, 5, 2, 3, 6)).buffered()
    println(source.indexOf(ByteString(byteArrayOf(3, 4, 5))))
    println(source.indexOf(ByteString(byteArrayOf(2, 3)), 2))
    println(source.indexOf(ByteString(byteArrayOf(7))))
    println(source.indexOf(ByteString(), 100))
    println(source.readByteString(4))
    println(source.readByteString())
    println(source.exhausted())

    val rawSink = ByteStringRecordingSink()
    val sink = rawSink.buffered()
    sink.write(ByteString(byteArrayOf(10, 11, 12)))
    println(rawSink.output.size)
    sink.flush()
    println(rawSink.output.snapshot())
    sink.write(ByteString(byteArrayOf(13, 14, 15)), 1)
    sink.close()
    println(rawSink.output.readByteString())
}
