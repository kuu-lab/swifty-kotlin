import kotlinx.io.*

// Exercises Buffer.peek() (PeekSource + Core.kt's buffered() extension, both resolved
// intra-package) and discardingSink() (a plain top-level function returning RawSink, backed by
// an internal class). Known gap: calling `.buffered()` from user code on a *user-defined* class
// implementing RawSource/RawSink is not covered here — see docs/kotlinx-io-status.md.

fun main() {
    val buf = Buffer()
    buf.write(byteArrayOf(1, 2, 3, 4, 5), 0, 5)
    val peeked = buf.peek()
    println(peeked.readByte())
    println(peeked.readByte())
    println(buf.readByte())
    println(buf.readByte())
    println(buf.readByte())
    println(buf.exhausted())

    val sink = discardingSink()
    val toDiscard = Buffer()
    toDiscard.write(byteArrayOf(9, 8, 7), 0, 3)
    sink.write(toDiscard, 3L)
    println(toDiscard.size)
    sink.flush()
    sink.close()
}
