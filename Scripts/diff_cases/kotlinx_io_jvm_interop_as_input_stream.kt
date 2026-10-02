import kotlinx.io.*

// KSP-1553: Source.asInputStream() adapter. KSwiftK drains the source eagerly
// into a ByteArrayInputStream (upstream is lazy), but the observable read and
// available() results match for a fully-populated source.
fun main() {
    val source = Buffer()
    source.write(byteArrayOf(7, 8, 9), 0, 3)
    val stream = source.asInputStream()
    println(stream.available())
    println(stream.read())
    println(stream.read())
    println(stream.read())
    println(stream.read())
    stream.close()
}
