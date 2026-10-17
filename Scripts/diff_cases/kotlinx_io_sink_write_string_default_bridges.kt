import java.io.IOException
import kotlinx.io.Buffer
import kotlinx.io.RawSink
import kotlinx.io.buffered
import kotlinx.io.readString
import kotlinx.io.writeString

private fun expectFailure(label: String, action: () -> Unit) {
    try {
        action()
        println("$label=NO_EXCEPTION")
    } catch (_: IndexOutOfBoundsException) {
        println("$label=IndexOutOfBoundsException")
    } catch (_: IllegalArgumentException) {
        println("$label=IllegalArgumentException")
    } catch (_: IllegalStateException) {
        println("$label=IllegalStateException")
    } catch (_: IOException) {
        println("$label=IOException")
    }
}

private fun closedRawSink() = object : RawSink {
    override fun write(source: Buffer, byteCount: Long) {
        source.skip(byteCount)
    }

    override fun flush() = Unit
    override fun close() = Unit
}.buffered()

private fun failingRawSink() = object : RawSink {
    override fun write(source: Buffer, byteCount: Long) {
        throw IOException("sink-write-failure")
    }

    override fun flush() = Unit
    override fun close() = Unit
}.buffered()

fun main() {
    val string: String = "012345"
    println("string-all=" + Buffer().apply { writeString(string) }.readString())
    println("string-default-end=" + Buffer().apply { writeString(string, startIndex = 2) }.readString())
    println("string-default-start=" + Buffer().apply { writeString(string, endIndex = 4) }.readString())
    println("string-explicit-range=" + Buffer().apply { writeString(string, 1, 4) }.readString())

    expectFailure("string-negative-start") {
        Buffer().writeString(string, startIndex = -1)
    }
    expectFailure("string-reversed-range") {
        Buffer().writeString(string, startIndex = 4, endIndex = 2)
    }
    expectFailure("string-end-out-of-range") {
        Buffer().writeString(string, endIndex = 7)
    }
    val closedStringSink = closedRawSink()
    closedStringSink.close()
    expectFailure("string-closed-sink") { closedStringSink.writeString(string) }
    expectFailure("string-io-failure") { failingRawSink().writeString("x".repeat(8192)) }

    val chars: CharSequence = StringBuilder("abcdef")
    println("charsequence-all=" + Buffer().apply { writeString(chars) }.readString())
    println("charsequence-default-end=" + Buffer().apply { writeString(chars, startIndex = 2) }.readString())
    println("charsequence-default-start=" + Buffer().apply { writeString(chars, endIndex = 4) }.readString())
    println("charsequence-explicit-range=" + Buffer().apply { writeString(chars, 1, 4) }.readString())

    expectFailure("charsequence-negative-start") {
        Buffer().writeString(chars, startIndex = -1)
    }
    expectFailure("charsequence-reversed-range") {
        Buffer().writeString(chars, startIndex = 4, endIndex = 2)
    }
    expectFailure("charsequence-end-out-of-range") {
        Buffer().writeString(chars, endIndex = 7)
    }
    val closedCharSequenceSink = closedRawSink()
    closedCharSequenceSink.close()
    expectFailure("charsequence-closed-sink") { closedCharSequenceSink.writeString(chars) }
    val longChars: CharSequence = StringBuilder("x".repeat(8192))
    expectFailure("charsequence-io-failure") { failingRawSink().writeString(longChars) }
}
