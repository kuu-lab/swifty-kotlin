// KUU-948: an unqualified member call on the implicit receiver inside an
// extension body must resolve even when same-named scope candidates that
// cannot satisfy the receiver are also visible (e.g. String.toInt from the
// kotlin.text default import, or an extension on an unrelated type).
// Previously this failed with "No viable overload" / "unresolved" and only
// `this.member(...)` worked.

class Sink {
    var written = 0
    fun write(value: Int) {
        written += value
    }
    fun flush() {
        written += 1000
    }
}

// Same simple name as Sink's member but an unrelated receiver: it must not
// mask the member candidate during unqualified resolution.
fun String.write(value: Int) {}

fun Sink.emit(value: Int) {
    write(value)
    flush()
}

// Unqualified member call inside a nested lambda without its own receiver:
// the enclosing extension's `this` still applies.
fun Sink.emitLater(value: Int): () -> Unit = { write(value) }

private fun Short.reverseBytes(): Short {
    val i = toInt() and 0xffff
    return ((i and 0xff00 ushr 8) or (i and 0x00ff shl 8)).toShort()
}

fun main() {
    val sink = Sink()
    sink.emit(42)
    sink.emitLater(8)()
    println(sink.written)
    println(0x1234.toShort().reverseBytes().toInt() and 0xffff)
}
