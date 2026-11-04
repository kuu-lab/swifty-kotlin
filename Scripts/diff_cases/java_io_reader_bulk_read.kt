import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.io.Reader
import java.io.StringReader

class CountingReader(private val source: String) : Reader() {
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
    // KUU-4044: Reader.read(CharArray) — the JVM convenience overload that
    // delegates to read(cbuf, 0, cbuf.length).
    val sr = StringReader("line1\nline2")
    val buf = CharArray(4)
    println(sr.read(buf))
    println(String(buf))
    println(sr.read(buf))
    println(String(buf))
    println(sr.read(buf))

    // Partial fill then EOF on a StringReader.
    val partial = StringReader("ab")
    val pbuf = CharArray(4)
    println(partial.read(pbuf))
    println(partial.read(pbuf))

    // Same shape through a BufferedReader box.
    val br = BufferedReader(StringReader("Hello"))
    val bbuf = CharArray(8)
    println(br.read(bbuf))
    println(String(bbuf))
    println(br.read(bbuf))

    // Reader-typed receivers: box and Kotlin-source objects both bulk-read.
    val boxedReader: Reader = BufferedReader(StringReader("abcdef"))
    val rbuf = CharArray(3)
    println(boxedReader.read(rbuf))
    println(String(rbuf))
    println(boxedReader.read(rbuf))
    println(boxedReader.read(rbuf))

    val kotlinReader: Reader = StringReader("wxyz")
    val kbuf = CharArray(2)
    println(kotlinReader.read(kbuf))
    println(String(kbuf))
    println(kotlinReader.read(kbuf))
    println(kotlinReader.read(kbuf))

    // Chained 3-arg reads keep the cursor where the last call stopped.
    val chained: Reader = StringReader("123456789")
    val cbuf = CharArray(6)
    println(chained.read(cbuf, 0, 4))
    println(chained.read(cbuf, 4, 2))
    println(String(cbuf))
    println(chained.read(cbuf))
    println(chained.read(cbuf))

    // User-defined Reader subclass through both receiver shapes.
    val custom = CountingReader("qwer")
    val ubuf = CharArray(3)
    println(custom.read(ubuf))
    println(String(ubuf))
    val customRef: Reader = CountingReader("asdf")
    println(customRef.read(ubuf))
    println(String(ubuf))
    println(customRef.read(ubuf))

    // InputStreamReader inherits the same overload.
    val isr = InputStreamReader("ios".byteInputStream())
    val ibuf = CharArray(5)
    println(isr.read(ibuf))
    println(String(ibuf))

    // JVM bounds contract: IndexOutOfBoundsException before any read.
    val bounds = StringReader("abc")
    try { bounds.read(buf, -1, 2); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-neg-off") }
    try { bounds.read(buf, 0, -1); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-neg-len") }
    try { bounds.read(buf, 3, 2); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-overrun") }
    try { bounds.read(buf, 5, 0); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-past-end") }
    val boxBounds = BufferedReader(StringReader("abc"))
    try { boxBounds.read(buf, 2, 3); println("no-throw") } catch (e: IndexOutOfBoundsException) { println("ioobe-box") }

    // len == 0 returns 0 without consuming.
    println(bounds.read(buf, 0, 0))
    println(bounds.read(CharArray(0)))
    println(bounds.read(buf))

    // Closed Kotlin reader surfaces IOException through both overloads.
    val closed = StringReader("abc")
    closed.close()
    try { closed.read(buf) } catch (e: IOException) { println("ioe-1arg") }
    try { closed.read(buf, 0, 2) } catch (e: IOException) { println("ioe-3arg") }
}
