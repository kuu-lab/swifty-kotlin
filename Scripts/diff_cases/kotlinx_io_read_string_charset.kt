import kotlinx.io.*
import kotlin.text.Charsets

fun main() {
    val buffer = Buffer()
    buffer.writeString("héllo")
    println(buffer.readString(3L))
    println(buffer.readString())
    println(buffer.size)
    buffer.write(byteArrayOf(233.toByte(), 65))
    println(buffer.readString(1L, Charsets.ISO_8859_1))
    val source: Source = buffer
    println(source.readString(Charsets.US_ASCII))
    println(source.readString())
    buffer.write(byteArrayOf(65, 0, 66, 0))
    println(buffer.readString(charset = Charsets.UTF_16LE))
    buffer.writeString("tail")
    try { buffer.readString(-1L, Charsets.UTF_8) }
    catch (e: IllegalArgumentException) { println("negative") }
    try { buffer.readString(5L, Charsets.UTF_8) }
    catch (e: EOFException) { println("eof") }
    println(buffer.readString())
    val upstream = Buffer()
    upstream.writeString("buffered")
    val raw: RawSource = upstream
    println(raw.buffered().readString(Charsets.UTF_8))
}
