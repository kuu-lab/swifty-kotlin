import kotlinx.io.*

// KSP-1553: InputStream.asSource() adapter — lazy reads flow through the
// synthetic java.io InputStream members byte by byte; buffered() is the
// KSP-1549 extension on RawSource.
fun main() {
    val bytes = byteArrayOf(10, 20, 30, 40)
    val source = bytes.inputStream().asSource().buffered()
    println(source.readByte())
    println(source.readByte())
    println(source.readByte())
    println(source.readByte())
    println(source.exhausted())
    source.close()
}
