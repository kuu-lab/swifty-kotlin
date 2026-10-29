import java.io.IOException
import kotlinx.io.*

fun main() {
    val buffer = Buffer()
    val stream = buffer.asOutputStream()
    stream.write(255)
    stream.write(byteArrayOf(10, 20, 30), 1, 2)
    stream.write(byteArrayOf())
    println(buffer.size)
    while (buffer.size > 0) println(buffer.readByte().toInt())

    val target = Buffer()
    val buffered = (target as RawSink).buffered().asOutputStream()
    buffered.write(65)
    buffered.close()
    println(target.readByte())
    try { buffered.write(66); println("unexpected") } catch (e: IOException) { println("closed") }
}
