import kotlinx.io.Buffer
import kotlinx.io.Sink
import kotlinx.io.Source

fun primitives(buffer: Buffer): Long {
    val sink: Sink = buffer
    sink.writeByte(1)
    sink.writeShort(2)
    sink.writeInt(3)
    sink.writeLong(4L)
    sink.write(byteArrayOf(5, 6), 0, 2)
    sink.write(byteArrayOf(7, 8))
    sink.hintEmit()
    sink.emit()
    sink.flush()
    val source: Source = buffer
    source.require(1L)
    source.request(2L)
    source.readByte()
    source.readShort()
    source.readInt()
    source.readLong()
    source.skip(1L)
    source.readAtMostTo(ByteArray(1), 0, 1)
    source.readAtMostTo(ByteArray(1))
    source.exhausted()
    source.buffer
    sink.buffer
    return buffer.size
}
