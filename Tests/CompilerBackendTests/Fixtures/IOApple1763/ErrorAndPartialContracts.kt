@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package kuu1763errorcontracts

import kotlinx.cinterop.*
import kotlinx.io.*
import platform.Foundation.*
import platform.posix.uint8_tVar
import kotlin.test.*

// These subtypes contain real SDK streams; only their typed Kotlin read/write
// overrides inject failures/partial results at the public receiver boundary.
private class FailedInput : NSInputStream(NSData()) {
    override fun read(buffer: CPointer<uint8_tVar>?, maxLength: ULong): Long = -1L
    override fun streamError(): NSError = NSError("test", 7L,
        mapOf(NSLocalizedDescriptionKey to "read failed"))
}
private class ShortOutput : NSOutputStream(Unit) {
    override fun write(buffer: CPointer<uint8_tVar>?, maxLength: ULong): Long =
        super.write(buffer, minOf(maxLength, 2uL))
}
private class ZeroOutput : NSOutputStream(Unit) {
    override fun write(buffer: CPointer<uint8_tVar>?, maxLength: ULong): Long = 0L
}
private class FailedOutput : NSOutputStream(Unit) {
    override fun write(buffer: CPointer<uint8_tVar>?, maxLength: ULong): Long = -1L
    override fun streamError(): NSError = NSError("test", 8L,
        mapOf(NSLocalizedDescriptionKey to "write failed"))
}
public fun runErrorAndPartialContracts() {
    val destination = Buffer()
    val input = FailedInput().asSource()
    // Exact pinned 0.9.1 clamp semantics: native -1 is committed as zero and
    // observed as EOF. This is not an assertion of an upstream IOException fix.
    assertEquals(-1L, input.readAtMostTo(destination, 3L))
    assertEquals(0L, destination.size)
    input.close()
    println("read failure: true")
    val short = ShortOutput()
    val bytes = Buffer().apply { writeString("abcdef") }
    short.asSink().write(bytes, 6L)
    assertEquals(0L, bytes.size)
    assertEquals("abcdef", (short.propertyForKey(NSStreamDataWrittenToMemoryStreamKey) as NSData)
        .toByteStringForContract())
    short.close()
    println("short write: true")
    val zero = Buffer().apply { writeString("keep") }
    val zeroOutput = ZeroOutput().asSink()
    assertFailsWith<IOException> { zeroOutput.write(zero, 4L) }
    assertEquals("keep", zero.readString())
    zeroOutput.close()
    println("zero write: true")
    val failed = Buffer().apply { writeString("keep") }
    val failedOutput = FailedOutput().asSink()
    assertEquals("write failed", assertFailsWith<IOException> { failedOutput.write(failed, 4L) }.message)
    assertEquals("keep", failed.readString())
    failedOutput.close()
    println("write failure: true")
    println("done")
}
private fun NSData.toByteStringForContract(): String = bytes!!.readBytes(length.toInt()).decodeToString()
