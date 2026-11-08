// KUU-4440: bundled java.io.PipedReader/PipedWriter.
// Covers connect() variants, blocking buffer hand-off across threads,
// close/EOF semantics, ready(), skip(), and IOException messages.
import java.io.PipedReader
import java.io.PipedWriter
import java.lang.Thread

fun attempt(label: String, block: () -> Unit) {
    try {
        block()
        println("$label => OK")
    } catch (e: Exception) {
        println("$label => ${e.javaClass.simpleName}: ${e.message}")
    }
}

fun main() {
    val r1 = PipedReader()
    attempt("read-unconnected") { r1.read() }
    val w1 = PipedWriter()
    attempt("write-unconnected") { w1.write(65) }
    attempt("write-str-unconnected") { w1.write("hi") }

    val r2 = PipedReader()
    val w2 = PipedWriter()
    r2.connect(w2)
    attempt("connect-twice") { r2.connect(PipedWriter()) }
    attempt("writer-connect-twice") { w2.connect(PipedReader()) }
    w2.write("hello")
    println("read1=" + r2.read())
    val buf = CharArray(4)
    val n = r2.read(buf, 0, 4)
    println("readN=$n rest=${String(buf, 0, n)}")
    println("ready=" + r2.ready())
    w2.close()
    println("after-close-read=" + r2.read())
    attempt("write-after-wclose") { w2.write(66) }
    r2.close()
    attempt("write-after-rclose") { w2.write(67) }
    println("markSupported=" + r2.markSupported())

    // Constructor-time connect + skip + multi-char write/read.
    val r3 = PipedReader()
    val w3 = PipedWriter(r3)
    w3.write(CharArray(10) { 'a' + it })
    println("skip=" + r3.skip(3))
    val all = CharArray(7)
    val got = r3.read(all, 0, 7)
    println("got=$got text=${String(all, 0, got)}")
    w3.close()
    r3.close()

    // Blocking hand-off: 3000 chars exceed the 1024-char pipe buffer.
    val r4 = PipedReader()
    val w4 = PipedWriter()
    r4.connect(w4)
    val reader = Thread {
        val data = CharArray(3000)
        var total = 0
        while (total < 3000) {
            val k = r4.read(data, total, 3000 - total)
            if (k < 0) break
            total += k
        }
        println("reader-got=$total first=${data[0]} last=${data[2999]}")
    }
    reader.start()
    val payload = CharArray(3000) { 'a' + (it % 26) }
    w4.write(payload)
    w4.close()
    reader.join()
    println("pipe-done")
}
