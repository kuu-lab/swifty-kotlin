import kotlinx.io.*

@OptIn(InternalIoApi::class)
fun main() {
    val buffer = Buffer()
    println(buffer.request(0L))
    println(buffer.readAtMostTo(ByteArray(0), 0, 0))
    println(buffer.readAtMostTo(Buffer(), 0L))
    buffer.writeInt(0x01020304)
    println(buffer.readAtMostTo(ByteArray(0), 0, 0))
    println(buffer.readAtMostTo(Buffer(), 0L))
    try {
        buffer.require(5L)
    } catch (e: kotlinx.io.EOFException) {
        println("require:${buffer.size}")
    }
    try {
        buffer.readLong()
    } catch (e: kotlinx.io.EOFException) {
        println("long:${buffer.size}")
    }
    try {
        buffer.skip(5L)
    } catch (e: kotlinx.io.EOFException) {
        println("skip:${buffer.size}")
    }
    buffer.writeShort(0x1234)
    val sink = Buffer()
    try {
        buffer.readTo(sink, 3L)
    } catch (e: kotlinx.io.EOFException) {
        println("readTo:${buffer.size}:${sink.size}")
    }
    val raw: RawSource = sink
    try {
        buffer.write(raw, 3L)
    } catch (e: kotlinx.io.EOFException) {
        println("write:${buffer.size}:${sink.size}")
    }
    try {
        buffer.write(buffer, 0L)
    } catch (e: IllegalArgumentException) {
        println("self")
    }
    try {
        buffer.request(-1L)
    } catch (e: IllegalArgumentException) {
        println("negative request")
    }
    try {
        buffer.skip(-1L)
    } catch (e: IllegalArgumentException) {
        println("negative skip:${buffer.size}")
    }
    try {
        buffer.copyTo(sink, 2L, 1L)
    } catch (e: IllegalArgumentException) {
        println("reversed copy")
    }
    try {
        buffer.get(buffer.size)
    } catch (e: IndexOutOfBoundsException) {
        println("bounds")
    }
    println(buffer.use { it.readShort() })
    buffer.writeByte(7)
    buffer.close()
    buffer.flush()
    buffer.emit()
    buffer.hintEmit()
    println(buffer.readByte())
    println(buffer.exhausted())
    val defaultSink: Sink = buffer
    defaultSink.write(byteArrayOf(8, 9, 10))
    val defaultSource: Source = buffer
    val defaultBytes = ByteArray(2)
    println(defaultSource.readAtMostTo(defaultBytes))
    println(defaultBytes.joinToString(","))
    buffer.write(byteArrayOf(11, 12))
    println(buffer.size)

    val shortBuffer = Buffer()
    shortBuffer.write(byteArrayOf(1, 2, 3))
    val shortRaw: RawSource = shortBuffer
    val shortSource = shortRaw.buffered()
    try {
        shortSource.skip(5L)
    } catch (e: kotlinx.io.EOFException) {
        println("buffered skip:${shortBuffer.size}:${shortSource.exhausted()}")
    }
}
