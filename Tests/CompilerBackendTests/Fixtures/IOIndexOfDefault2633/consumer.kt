package kuu2633

import kotlinx.io.indexOf as ioIndexOf
import kotlinx.io.bytestring.ByteString

private fun argumentFailure(block: () -> Long): String = try {
    block()
    "NONE"
} catch (_: IllegalArgumentException) {
    "IllegalArgumentException"
} catch (_: IndexOutOfBoundsException) {
    "IndexOutOfBoundsException"
} catch (_: Throwable) {
    "OTHER"
}

fun main() {
    val buffer = newIndexOfBuffer()
    println("buffer-byte-default:${buffer.ioIndexOf(20.toByte())}")
    println("buffer-byte-start-default-end:${buffer.ioIndexOf(20.toByte(), 2L)}")
    println("buffer-byte-explicit-range:${buffer.ioIndexOf(20.toByte(), 0L, 2L)}")
    println("buffer-byte-invalid:${argumentFailure { buffer.ioIndexOf(20.toByte(), -1L) }}")
    println("buffer-byte-reversed-range:${argumentFailure { buffer.ioIndexOf(20.toByte(), 2L, 1L) }}")

    val byteString = ByteString(byteArrayOf(30, 20))
    println("buffer-bytestring-default:${buffer.ioIndexOf(byteString)}")
    println("buffer-bytestring-offset:${buffer.ioIndexOf(byteString, 3L)}")

    val source = newIndexOfSource()
    println("source-byte-default:${source.ioIndexOf(20.toByte())}")
    println("source-byte-start-default-end:${source.ioIndexOf(20.toByte(), 2L)}")
    println("source-byte-invalid:${argumentFailure { source.ioIndexOf(20.toByte(), -1L) }}")
    println("source-bytestring-default:${source.ioIndexOf(byteString)}")
    println("source-bytestring-offset:${source.ioIndexOf(byteString, 3L)}")
}
