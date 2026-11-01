import java.io.BufferedReader
import java.io.IOException
import java.io.Reader
import java.io.StringReader
import java.io.StringWriter

class PrefixReader(private val source: String) : Reader() {
    private var index = 0
    private var closed = false

    override fun read(buffer: CharArray, offset: Int, length: Int): Int {
        if (closed) throw IOException("closed")
        if (offset < 0 || length < 0 || offset > buffer.size - length) {
            throw IndexOutOfBoundsException()
        }
        if (length == 0) return 0
        if (index >= source.length) return -1
        var copied = 0
        while (copied < length && index < source.length) {
            buffer[offset + copied] = source[index]
            copied += 1
            index += 1
        }
        return copied
    }

    override fun close() {
        closed = true
    }
}

fun main() {
    val lines = BufferedReader(StringReader("l1\nl2"))
    println(lines.readLine())
    println(lines.readLine())
    println(lines.readLine())

    val chars = BufferedReader(StringReader("x\ny"))
    println(chars.ready())
    println(chars.read())
    println(chars.readLine())
    println(chars.readLine())

    println(BufferedReader(StringReader("p\nq")).readLines())

    val custom = BufferedReader(PrefixReader("c1\nc2"))
    println(custom.readLine())
    println(custom.readLine())

    val textReader: Reader = StringReader("tail")
    println(textReader.readText())

    val sink = StringWriter()
    StringReader("copied").copyTo(sink)
    println(sink.toString())

    val rangeReader: Reader = BufferedReader(StringReader("abcdef"))
    val buffer = CharArray(4)
    buffer[0] = ' '
    println(rangeReader.read(buffer, 1, 3))
    println(String(buffer))

    println(BufferedReader(BufferedReader(StringReader("deep"))).readLine())
    val any: Reader = BufferedReader(StringReader("k"))
    println(any is BufferedReader)
    println(any is Reader)
    println((any as BufferedReader).readLine())

    BufferedReader(StringReader("useline")).use { println(it.readLine()) }
}
