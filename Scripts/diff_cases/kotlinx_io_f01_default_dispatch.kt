import kotlinx.io.*

// KUU-1820: interface defaults must select the upstream single-parameter
// signatures for concrete, interface-typed, and foreign Raw* consumers.
private class F01RawSource(private val bytes: ByteArray) : RawSource {
    private var position = 0

    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (position == bytes.size) return -1L
        val count = minOf(byteCount.toInt(), bytes.size - position)
        sink.write(bytes, position, position + count)
        position += count
        return count.toLong()
    }

    override fun close() {}
}

private class F01RawSink : RawSink {
    val buffer = Buffer()

    override fun write(source: Buffer, byteCount: Long) {
        buffer.write(source, byteCount)
    }

    override fun flush() {}
    override fun close() {}
}

private fun drain(buffer: Buffer): String {
    val bytes = ByteArray(buffer.size.toInt())
    buffer.readAtMostTo(bytes)
    return String(bytes)
}

private fun appendDefaultForms(sink: Sink) {
    val bytes = byteArrayOf(65, 66, 67, 68)
    sink.write(bytes)
    sink.write(bytes, 1)
    sink.write(bytes, startIndex = 2)
}

private fun readDefaultForm(source: Source, startIndex: Int): String {
    val bytes = ByteArray(5) { 46 }
    val count = source.readAtMostTo(bytes, startIndex)
    return "$count:${String(bytes)}"
}

private fun readDefaultEndIndex(source: Source): String {
    val bytes = ByteArray(5) { 46 }
    val count = source.readAtMostTo(bytes, endIndex = 3)
    return "$count:${String(bytes)}"
}

fun main() {
    val concreteBuffer = Buffer()
    appendDefaultForms(concreteBuffer)
    println(drain(concreteBuffer))

    val interfaceBuffer: Sink = Buffer()
    appendDefaultForms(interfaceBuffer)
    println(drain(interfaceBuffer as Buffer))

    val foreignRawSink: RawSink = F01RawSink()
    val foreignSink: Sink = foreignRawSink.buffered()
    appendDefaultForms(foreignSink)
    foreignSink.flush()
    println(drain((foreignRawSink as F01RawSink).buffer))

    val concreteSource = Buffer()
    concreteSource.write(byteArrayOf(65, 66, 67, 68))
    println(readDefaultForm(concreteSource, 1))

    val interfaceSourceBuffer = Buffer()
    interfaceSourceBuffer.write(byteArrayOf(65, 66, 67, 68))
    val interfaceSource: Source = interfaceSourceBuffer
    println(readDefaultForm(interfaceSource, 1))

    val foreignRawSource: RawSource = F01RawSource(byteArrayOf(65, 66, 67, 68))
    println(readDefaultForm(foreignRawSource.buffered(), 1))

    val endIndexSource = Buffer()
    endIndexSource.write(byteArrayOf(65, 66, 67, 68))
    println(readDefaultEndIndex(endIndexSource))
}
