import kotlinx.io.*

// Exercises RawSource.buffered()/RawSink.buffered() on user-defined Raw* implementations
// (RealSource/RealSink internals: close propagation and flush timing), Buffer.peek()
// (PeekSource + Core.kt's buffered() extension), and discardingSink().

class ListRawSource(private val bytes: ByteArray) : RawSource {
    private var pos = 0
    var closed = false

    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (pos >= bytes.size) {
            return -1L
        }
        val remaining = bytes.size - pos
        val n = if (byteCount.toInt() < remaining) byteCount.toInt() else remaining
        sink.write(bytes, pos, pos + n)
        pos += n
        return n.toLong()
    }

    override fun close() {
        closed = true
    }
}

class CollectRawSink : RawSink {
    val collected = Buffer()
    var flushed = 0
    var closed = false

    override fun write(source: Buffer, byteCount: Long) {
        collected.write(source, byteCount)
    }

    override fun flush() {
        flushed += 1
    }

    override fun close() {
        closed = true
    }
}

fun main() {
    // buffered() read path: RealSource bulk-reads from the raw source into its buffer.
    val src = ListRawSource(byteArrayOf(65, 66, 67, 68))
    val buffered = src.buffered()
    println(buffered.readByte())
    println(buffered.readShort())
    println(buffered.exhausted())
    println(buffered.readByte())
    println(buffered.exhausted())
    buffered.close()
    println(src.closed)

    // peek() (PeekSource -> buffered()).
    val buf = Buffer()
    buf.write(byteArrayOf(1, 2, 3, 4, 5), 0, 5)
    val peeked = buf.peek()
    println(peeked.readByte())
    println(peeked.readByte())
    println(buf.readByte())
    println(buf.readByte())
    println(buf.readByte())
    println(buf.exhausted())

    // buffered() write path: RealSink holds writes in its buffer until flush/close.
    val raw = CollectRawSink()
    val sink = raw.buffered()
    sink.writeByte(10)
    sink.writeByte(20)
    sink.writeShort(0x1A2B.toShort())
    println(raw.collected.size)
    sink.flush()
    println(raw.collected.size)
    println(raw.flushed)
    sink.writeByte(30)
    sink.close()
    println(raw.collected.size)
    println(raw.closed)

    // discardingSink() swallows everything written to it.
    val disc = discardingSink()
    val toDiscard = Buffer()
    toDiscard.write(byteArrayOf(9, 8, 7), 0, 3)
    disc.write(toDiscard, 3L)
    println(toDiscard.size)
    disc.flush()
    disc.close()
}
