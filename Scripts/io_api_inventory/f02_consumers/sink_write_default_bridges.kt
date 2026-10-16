import kotlinx.io.Buffer
import kotlinx.io.IOException
import kotlinx.io.RawSink
import kotlinx.io.Sink
import kotlinx.io.buffered
import kotlinx.io.readByteArray
import kotlinx.io.bytestring.ByteString
import kotlinx.io.write

private fun drain(buffer: Buffer): String = buffer.readByteArray().joinToString(",")

private fun reportFailure(label: String, expected: String, failure: Throwable?) {
    val actual = when (failure) {
        null -> "NONE"
        is IOException -> "IOException"
        is IndexOutOfBoundsException -> "IndexOutOfBoundsException"
        is IllegalArgumentException -> "IllegalArgumentException"
        is IllegalStateException -> "IllegalStateException"
        else -> "Unexpected:${failure::class.simpleName}"
    }
    println("$label:$actual")
    check(actual == expected) { "$label expected $expected but got $actual" }
}

private fun attemptArrayDefault(label: String, expected: String, sink: Sink, source: ByteArray) {
    var failure: Throwable? = null
    try {
        sink.write(source)
    } catch (caught: Throwable) {
        failure = caught
    }
    reportFailure(label, expected, failure)
}

private fun attemptArrayRange(
    label: String,
    expected: String,
    sink: Sink,
    source: ByteArray,
    startIndex: Int,
    endIndex: Int,
) {
    var failure: Throwable? = null
    try {
        sink.write(source, startIndex, endIndex)
    } catch (caught: Throwable) {
        failure = caught
    }
    reportFailure(label, expected, failure)
}

private fun attemptByteStringDefault(label: String, expected: String, sink: Sink, source: ByteString) {
    var failure: Throwable? = null
    try {
        sink.write(source)
    } catch (caught: Throwable) {
        failure = caught
    }
    reportFailure(label, expected, failure)
}

private fun attemptByteStringRange(
    label: String,
    expected: String,
    sink: Sink,
    source: ByteString,
    startIndex: Int,
    endIndex: Int,
) {
    var failure: Throwable? = null
    try {
        sink.write(source, startIndex, endIndex)
    } catch (caught: Throwable) {
        failure = caught
    }
    reportFailure(label, expected, failure)
}

private fun openSink(): Sink = object : RawSink {
    override fun write(source: Buffer, byteCount: Long) {
        source.skip(byteCount)
    }

    override fun flush() {}
    override fun close() {}
}.buffered()

private fun failingSink(): Sink = object : RawSink {
    override fun write(source: Buffer, byteCount: Long) {
        throw IOException("probe")
    }

    override fun flush() {}
    override fun close() {}
}.buffered()

fun main() {
    val array = byteArrayOf(1, 2, 3, 4)

    val arrayDefaultBuffer = Buffer()
    val arrayDefaultSink: Sink = arrayDefaultBuffer
    arrayDefaultSink.write(array)
    println("bytearray-default:${drain(arrayDefaultBuffer)}")

    val arrayStartBuffer = Buffer()
    val arrayStartSink: Sink = arrayStartBuffer
    arrayStartSink.write(array, 1)
    println("bytearray-start-default-end:${drain(arrayStartBuffer)}")

    val arrayRangeBuffer = Buffer()
    val arrayRangeSink: Sink = arrayRangeBuffer
    arrayRangeSink.write(array, 1, 3)
    println("bytearray-range:${drain(arrayRangeBuffer)}")

    val arrayEmptyBuffer = Buffer()
    val arrayEmptySink: Sink = arrayEmptyBuffer
    arrayEmptySink.write(byteArrayOf())
    println("bytearray-empty:${arrayEmptyBuffer.size}")

    val byteString = ByteString(array)

    val byteStringDefaultBuffer = Buffer()
    val byteStringDefaultSink: Sink = byteStringDefaultBuffer
    byteStringDefaultSink.write(byteString)
    println("bytestring-default:${drain(byteStringDefaultBuffer)}")

    val byteStringStartBuffer = Buffer()
    val byteStringStartSink: Sink = byteStringStartBuffer
    byteStringStartSink.write(byteString, 1)
    println("bytestring-start-default-end:${drain(byteStringStartBuffer)}")

    val byteStringRangeBuffer = Buffer()
    val byteStringRangeSink: Sink = byteStringRangeBuffer
    byteStringRangeSink.write(byteString, 1, 3)
    println("bytestring-range:${drain(byteStringRangeBuffer)}")

    val byteStringEmptyBuffer = Buffer()
    val byteStringEmptySink: Sink = byteStringEmptyBuffer
    byteStringEmptySink.write(ByteString(byteArrayOf()))
    println("bytestring-empty:${byteStringEmptyBuffer.size}")

    val arrayNegativeStartSink: Sink = Buffer()
    attemptArrayRange("bytearray-negative-start", "IndexOutOfBoundsException", arrayNegativeStartSink, array, -1, 1)
    val arrayEndPastSizeSink: Sink = Buffer()
    attemptArrayRange("bytearray-end-past-size", "IndexOutOfBoundsException", arrayEndPastSizeSink, array, 0, 5)
    val arrayStartAfterEndSink: Sink = Buffer()
    attemptArrayRange("bytearray-start-after-end", "IllegalArgumentException", arrayStartAfterEndSink, array, 3, 2)

    val byteStringNegativeStartSink: Sink = Buffer()
    attemptByteStringRange("bytestring-negative-start", "IndexOutOfBoundsException", byteStringNegativeStartSink, byteString, -1, 1)
    val byteStringEndPastSizeSink: Sink = Buffer()
    attemptByteStringRange("bytestring-end-past-size", "IndexOutOfBoundsException", byteStringEndPastSizeSink, byteString, 0, 5)
    val byteStringStartAfterEndSink: Sink = Buffer()
    attemptByteStringRange("bytestring-start-after-end", "IllegalArgumentException", byteStringStartAfterEndSink, byteString, 3, 2)

    val closedArraySink = openSink()
    closedArraySink.close()
    attemptArrayDefault("bytearray-closed-sink", "IllegalStateException", closedArraySink, array)
    val closedByteStringSink = openSink()
    closedByteStringSink.close()
    attemptByteStringDefault("bytestring-closed-sink", "IllegalStateException", closedByteStringSink, byteString)

    attemptArrayDefault("bytearray-io-failure", "IOException", failingSink(), ByteArray(16_384))
    attemptByteStringDefault("bytestring-io-failure", "IOException", failingSink(), ByteString(ByteArray(16_384)))
}
