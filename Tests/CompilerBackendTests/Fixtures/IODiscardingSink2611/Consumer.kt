package kuu2611discardingsinkconsumer

import kotlinx.io.Buffer
import kotlinx.io.RawSink
import kotlinx.io.discardingSink
import kuu2611discardingsinkproducer.producerMarker

// API rows: jvm-04f9c66bafd8712c and klib-f24361849bd7cfdd.
private fun bufferOf(bytes: ByteArray): Buffer = Buffer().also {
    it.write(bytes, 0, bytes.size)
}

private fun failureName(block: () -> Unit): String {
    return try {
        block()
        "NONE"
    } catch (failure: Throwable) {
        failure::class.simpleName ?: "Throwable"
    }
}

public fun main() {
    println("producer")
    println(producerMarker())

    val sink: RawSink = discardingSink()
    val zero = bufferOf(byteArrayOf(122, 101, 114, 111))
    sink.write(zero, 0L)
    println("zero")
    println(zero.size)
    println(zero.readByte().toInt())

    val partial = bufferOf(byteArrayOf(97, 98, 99, 100, 101, 102))
    sink.write(partial, 2L)
    println("partial")
    println(partial.size)
    println(partial.readByte().toInt())
    println(partial.readByte().toInt())
    println(partial.readByte().toInt())
    println(partial.readByte().toInt())

    val exact = bufferOf(byteArrayOf(120, 121, 122))
    sink.write(exact, exact.size)
    println("exact")
    println(exact.size)

    val negative = bufferOf(byteArrayOf(110, 101, 103, 97, 116, 105, 118, 101))
    val negativeFailure = failureName { sink.write(negative, -1L) }
    println("negative")
    println(negativeFailure)
    println(negative.size)
    println(negative.readByte().toInt())

    val oversized = bufferOf(byteArrayOf(115, 104, 111, 114, 116))
    val oversizedFailure = failureName { sink.write(oversized, oversized.size + 1L) }
    println("oversized")
    println(oversizedFailure)
    println(oversized.size)

    val empty = Buffer()
    sink.write(empty, 0L)
    val emptyPositiveFailure = failureName { sink.write(empty, 1L) }
    println("empty-positive")
    println(emptyPositiveFailure)
    println(empty.size)

    val flushSink: RawSink = discardingSink()
    println("flush")
    println(failureName { flushSink.flush() })

    val closeSink: RawSink = discardingSink()
    val closeFailure = failureName { closeSink.close() }
    val repeatedCloseFailure = failureName { closeSink.close() }
    println("close")
    println(closeFailure)
    println(repeatedCloseFailure)

    val afterClose = bufferOf(byteArrayOf(97, 102, 116, 101, 114, 45, 99, 108, 111, 115, 101))
    val afterCloseFailure = failureName { closeSink.write(afterClose, afterClose.size) }
    val flushAfterCloseFailure = failureName { closeSink.flush() }
    println("write-after-close")
    println(afterCloseFailure)
    println(afterClose.size)
    println("flush-after-close")
    println(flushAfterCloseFailure)
}
