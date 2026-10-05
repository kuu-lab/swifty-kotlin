import kotlinx.io.*

class ArrayChunks(private val bytes: ByteArray) : RawSource {
    private var position = 0
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (position == bytes.size) return -1L
        val count = if (bytes.size - position < 2) bytes.size - position else 2
        sink.write(bytes, position, position + count)
        position += count
        return count.toLong()
    }
    override fun close() {}
}

fun arraySource(chunked: Boolean): Source {
    val bytes = byteArrayOf(1, 2, 3, 4, 5)
    if (chunked) return ArrayChunks(bytes).buffered()
    val buffer = Buffer()
    buffer.write(bytes)
    return buffer
}

fun main() {
    for (chunked in listOf(false, true)) {
        val exact = arraySource(chunked)
        val destination = ByteArray(7) { 9 }
        exact.readTo(destination, 1, 6)
        println(destination.joinToString())
        println(exact.exhausted())
        exact.readTo(ByteArray(0))
        println(exact.readAtMostTo(ByteArray(0)))

        val partial = arraySource(chunked)
        val array = ByteArray(7) { 9 }
        try { partial.readTo(array) } catch (e: EOFException) { println(e.message) }
        println(array.joinToString())
        println(partial.exhausted())

        val limited = arraySource(chunked)
        println(limited.readByteArray(0).size)
        try { limited.readByteArray(6) } catch (e: EOFException) { println("exact-eof") }
        println(limited.readByteArray(3).joinToString())
        println(limited.readByteArray().joinToString())
        println(limited.readByteArray().size)
        try { limited.readByteArray(-1) } catch (e: IllegalArgumentException) { println(e.message) }

        val atMost = arraySource(chunked)
        val out = ByteArray(3) { 9 }
        println(atMost.readAtMostTo(out))
        println(out.joinToString())
        println(atMost.readAtMostTo(out, 1))
        println(out.joinToString())
        println(atMost.readByteArray().joinToString())

        val namedEnd = arraySource(chunked)
        val namedOut = ByteArray(3) { 9 }
        println(namedEnd.readAtMostTo(namedOut, endIndex = 1))
        println(namedOut.joinToString())
        println(namedEnd.readByteArray().joinToString())

        val bounds = arraySource(chunked)
        try { bounds.readTo(ByteArray(2), -1, 2) } catch (e: IndexOutOfBoundsException) { println("negative-index") }
        try { bounds.readTo(ByteArray(2), 0, 3) } catch (e: IndexOutOfBoundsException) { println("large-index") }
        try { bounds.readTo(ByteArray(2), 2, 1) } catch (e: IllegalArgumentException) { println("reversed-index") }
        println(bounds.readByteArray().joinToString())
    }
    val direct = Buffer()
    direct.write(byteArrayOf(6, 7))
    val out = ByteArray(2)
    direct.readTo(out)
    println(out.joinToString())
}
