import kotlinx.io.*

fun main() {
    val buffer = Buffer()
    buffer.writeString("ASCII\u0000 é € 日本語 😀")
    println(buffer.size)
    println(buffer.readString())
    println(buffer.size)
    buffer.writeString("xé€😀y", 1, 5)
    println(buffer.size)
    println(buffer.readString(5L))
    println(buffer.readString())

    val chars: CharSequence = StringBuilder("Aé€😀Z")
    val sink: Sink = buffer
    sink.writeString(chars, 1, 5)
    println(buffer.size)
    println(buffer.readString())
    buffer.writeString("\ud800A\udc00\ud800\udc00\udbff\udfff")
    println(buffer.size)
    while (!buffer.exhausted()) println(buffer.readCodePointValue())
    buffer.writeString("😀", 0, 1)
    buffer.writeString("😀", 1, 2)
    println(buffer.readString())

    sink.writeCodePointValue(0)
    sink.writeCodePointValue(0x7f)
    sink.writeCodePointValue(0x80)
    sink.writeCodePointValue(0x7ff)
    sink.writeCodePointValue(0x800)
    sink.writeCodePointValue(0xd800)
    sink.writeCodePointValue(0xffff)
    sink.writeCodePointValue(0x10000)
    sink.writeCodePointValue(0x10ffff)
    val source: Source = buffer
    while (!source.exhausted()) println(source.readCodePointValue())
    try { sink.writeCodePointValue(-1) } catch (e: IllegalArgumentException) { println("negative") }
    try { sink.writeCodePointValue(0x110000) } catch (e: IllegalArgumentException) { println("too large") }
    try { sink.writeString("abc", -1, 2) } catch (e: IndexOutOfBoundsException) { println("bounds") }
    try { sink.writeString("abc", 2, 1) } catch (e: IllegalArgumentException) { println("reversed") }
    try { source.readString(-1L) } catch (e: IllegalArgumentException) { println("negative count") }
    try { source.readString(1L) } catch (e: EOFException) { println("empty") }
    println(source.readString(0L))
    println(source.readString())
}
