import java.io.ByteArrayOutputStream
import java.io.SequenceInputStream

fun main() {
    val stream = "abc".byteInputStream()
    println(stream.read())
    println(stream.available())
    println(stream.skip(1))
    println(stream.read())
    println(stream.markSupported())
    stream.close()

    val buffered = "xy".byteInputStream().buffered()
    println(buffered.read())
    println(buffered.available())
    buffered.close()

    val out = ByteArrayOutputStream()
    out.write(104)
    out.write(105)
    println(out.size())
    println(out.toString())
    println(out.toByteArray().size)
    out.close()

    val chained = SequenceInputStream("hi".byteInputStream(), "!".byteInputStream())
    println(chained.read())
    println(chained.read())
    println(chained.available())
    chained.close()

    var closed = false
    "z".byteInputStream().use { s ->
        println(s.read())
        closed = true
    }
    println(closed)

    println("bytes=" + "ab".byteInputStream().readBytes().size)

    val copyOut = ByteArrayOutputStream()
    println("copied=" + "data".byteInputStream().copyTo(copyOut))
    println(copyOut.toString())
}
