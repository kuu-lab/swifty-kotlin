import kotlinx.io.*

@OptIn(InternalIoApi::class)
fun main() {
    val buffer = Buffer()
    buffer.writeByte(1)
    buffer.writeByte(2)
    val beforeRead = buffer.peek()
    buffer.readByte()
    buffer.writeByte(2)
    try {
        println(beforeRead.readByte())
    } catch (e: IllegalStateException) {
        println("invalid before first peek read")
    }

    val empty = Buffer()
    val peekEmpty = empty.peek()
    println(peekEmpty.exhausted())
    empty.writeByte(3)
    empty.writeByte(4)
    println(peekEmpty.readByte())
    peekEmpty.skip(1L)
    println(empty.size)
    empty.readByte()
    empty.writeByte(5)
    try {
        peekEmpty.readByte()
    } catch (e: IllegalStateException) {
        println("invalid after upstream read")
    }

    val multi = Buffer()
    val bytes = ByteArray(8192)
    multi.write(bytes, 0, bytes.size)
    multi.writeByte(5)
    val peek = multi.peek()
    peek.skip(8192L)
    println(peek.readByte())
    println(multi.size)
    multi.skip(8192L)
    multi.writeByte(6)
    try {
        peek.readByte()
    } catch (e: IllegalStateException) {
        println("invalid at segment boundary")
    }

    val upstream = Buffer()
    val rawSink: RawSink = upstream
    val buffered = rawSink.buffered()
    buffered.write(bytes, 0, 8191)
    println(upstream.size)
    buffered.writeShort(0x1234)
    println(upstream.size)
    println(buffered.buffer.size)
    buffered.flush()
    println(upstream.size)
    println(buffered.buffer.exhausted())
    val chunk = Buffer()
    chunk.writeByte(7)
    chunk.copyTo(buffered.buffer)
    buffered.hintEmit()
    println(upstream.size)
    println(buffered.buffer.size)

    val rawSource: RawSource = upstream
    val destination = Buffer()
    println(destination.transferFrom(rawSource))
    println(destination.transferTo(Buffer()))
    println(upstream.exhausted())
}
