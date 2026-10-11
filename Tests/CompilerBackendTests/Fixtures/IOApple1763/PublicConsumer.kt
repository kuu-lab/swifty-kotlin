@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package kuu1763publicconsumer
import kotlinx.io.*
import kotlinx.io.bytestring.*
import kuu1763publicproducer.*
import platform.Foundation.*
import kotlin.test.*
public fun main() {
    val bytes = byteArrayOf(1, 2, 3)
    val data = copiedData(bytes)
    bytes.fill(9)
    assertContentEquals(byteArrayOf(1, 2, 3), copiedBytes(data).toByteArray())
    println("copy: true")
    val input = inputFromSource(Buffer().apply { writeString("abc") })
    val source = sourceFromInput(input).buffered()
    assertEquals("abc", source.readString())
    source.close()
    assertEquals(NSStreamStatusClosed, input.streamStatus)
    println("source: true")
    val buffer = Buffer()
    val output = outputFromSink(buffer)
    val sink = sinkFromOutput(output).buffered()
    sink.writeString("xyz")
    sink.flush()
    assertEquals("xyz", buffer.readString())
    sink.close()
    assertEquals(NSStreamStatusClosed, output.streamStatus)
    println("sink: true")
    errorAndPartialContracts()
    println("done")
}
