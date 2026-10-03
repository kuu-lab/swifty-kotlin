import kotlinx.io.*

// KSP-1553: OutputStream.asSink() adapter — writes go through the synthetic
// java.io OutputStream.write(Int) member byte by byte. Paired with
// Sink.asOutputStream() to produce an OutputStream handle (the only way to
// construct one from Kotlin source today).
fun main() {
    val buffer = Buffer()
    val out = buffer.asOutputStream()
    val sink = out.asSink().buffered()
    sink.write(byteArrayOf(1, 2, 3), 0, 3)
    sink.emit()
    println(buffer.size)
    println(buffer.readByte())
    println(buffer.readByte())
    println(buffer.readByte())
    out.close()
}
