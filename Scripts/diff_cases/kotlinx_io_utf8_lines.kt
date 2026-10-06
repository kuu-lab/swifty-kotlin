import kotlinx.io.*

fun main() {
    val buffer = Buffer()
    buffer.writeString("\nα\r\n😀\nlast\r")
    val source: Source = buffer.peek()
    println(source.request(1))
    println(source.indexOf(10))
    println(source.indexOf(10, 1L, 5L))
    println(source.indexOf(10, 5L, 5L))
    println(source.readLine())
    println(source.readLine())
    println(source.readLine())
    println(source.readLine())
    println(source.readLine())
    println(buffer.readString())

    buffer.writeString("é\r\nabc\n")
    println(buffer.readLineStrict(2L))
    try { buffer.readLineStrict(2L) } catch (e: EOFException) { println(buffer.size) }
    println(buffer.readLineStrict(3L))
    buffer.writeString("tail")
    try { buffer.readLineStrict() } catch (e: EOFException) { println(buffer.readString()) }
    buffer.writeString("\r\n")
    println(buffer.readLineStrict(0L))
    buffer.writeString("\n")
    println(buffer.readLineStrict(0L))
    try { buffer.readLineStrict(-1L) } catch (e: IllegalArgumentException) { println("negative limit") }

    var i = 0
    while (i < 8191) {
        buffer.writeByte(65)
        i += 1
    }
    buffer.writeString("😀\r\nnext")
    val peek: Source = buffer.peek()
    println(peek.indexOf(13))
    println(peek.readLineStrict(8195L).length)
    println(peek.readLine())
    println(peek.readLine())
    println(buffer.size)

    val out = discardingSink().buffered()
    out.close()
    try { out.writeString("") } catch (e: IllegalStateException) { println("closed sink") }
    peek.close()
    try { peek.readString(0L) } catch (e: IllegalStateException) { println("closed source") }
}
