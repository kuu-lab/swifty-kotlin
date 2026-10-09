import kotlinx.io.*
import java.io.IOException

// KSP-1553: Sink.asOutputStream() adapter — a bridge OutputStream whose
// write/flush/close forward into the Kotlin Sink through
// __kk_kotlin_sink_output_stream callbacks. Closed-state delegates to the
// underlying sink, matching upstream: a Buffer never reports closed, while a
// RealSink surfaces IOException("Underlying sink is closed.") on writes.
fun main() {
    val buffer = Buffer()
    val out = buffer.asOutputStream()
    out.write(65)
    out.write(66)
    out.flush()
    println(buffer.size)
    out.close()
    println(buffer.readByte())
    println(buffer.readByte())
    out.write(67)
    println(buffer.readByte())

    val bulkBuffer = Buffer()
    val bulkOut = bulkBuffer.asOutputStream()
    bulkOut.write(byteArrayOf(104, 105, 106, 0, 127, -128, -1))
    bulkOut.write(byteArrayOf())
    bulkOut.flush()
    println(bulkBuffer.size)
    while (bulkBuffer.size > 0) {
        println(bulkBuffer.readByte().toInt())
    }

    val rawBuffer = Buffer()
    val raw: RawSink = rawBuffer
    val buffered = raw.buffered()
    val bufferedOut = buffered.asOutputStream()
    bufferedOut.write(90)
    bufferedOut.close()
    println(rawBuffer.readByte())
    try {
        bufferedOut.write(91)
        println("no-throw")
    } catch (e: IOException) {
        println(e.message)
    }
    try {
        bufferedOut.write(byteArrayOf(104, 105, 106))
        println("no-throw")
    } catch (e: IOException) {
        println(e.message)
    }
}
