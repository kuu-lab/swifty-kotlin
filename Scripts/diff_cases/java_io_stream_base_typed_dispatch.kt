import java.io.BufferedWriter
import java.io.DataInputStream
import java.io.InputStream
import java.io.StringWriter
import java.io.Writer

// KUU-3851/KUU-3860: java.io values passed through base-typed receivers
// (InputStream / Writer) must dispatch through the registered vtable slot so
// Kotlin subclass overrides win, while runtime-produced boxes resolve the
// same __kk_* bridge a direct call would have used. Streams and readers
// also conform to java.io.Closeable / java.lang.AutoCloseable on the JVM.
fun useCloseable(c: java.io.Closeable) {
    c.close()
    println("closed-ok")
}

class FlushingWriter(w: Writer) : BufferedWriter(w) {
    override fun flush() {
        println("override-flush")
    }
}

fun main() {
    val s: InputStream = DataInputStream("abc".byteInputStream())
    println(s.read())
    useCloseable("abc".byteInputStream())
    println("abc".byteInputStream() is java.io.Closeable)
    println("abc".byteInputStream() is java.lang.AutoCloseable)
    // A base-typed runtime box dispatches to the same bridge it would have
    // called directly.
    val box: InputStream = "xyz".byteInputStream()
    println(box.read())

    // Raw BufferedReader boxes carry their nominal type and ancestry:
    // is-checks against Reader and every closeable interface must be true.
    val reader = "line".byteInputStream().bufferedReader()
    println(reader is java.io.BufferedReader)
    println(reader is java.io.Reader)
    println(reader is java.io.Closeable)
    println(reader is java.lang.AutoCloseable)

    // Writer-typed receivers dispatch write/flush/close through the slots
    // registered on the produced box (KUU-3860).
    val target = StringWriter()
    val writer: Writer = BufferedWriter(target)
    writer.write("hi")
    writer.flush()
    writer.close()
    println(target.toString())

    // A Kotlin subclass override still wins through the identical slot.
    val sub: Writer = FlushingWriter(StringWriter())
    sub.flush()

    // `use` lowers to an itable call on the concrete receiver type; runtime
    // boxes register their closeable iface->slot map ad hoc, so the lookup
    // must resolve by interface type ID rather than a class-layout slot
    // (KUU-3860: previously KSWIFTK-RUNTIME-0001).
    "z".byteInputStream().use { input ->
        println(input.read())
    }
}
