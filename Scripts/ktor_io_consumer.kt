@file:OptIn(kotlinx.io.UnsafeIoApi::class)

import io.ktor.utils.io.ByteChannel
import io.ktor.utils.io.ByteReadChannel
import io.ktor.utils.io.copyAndClose
import io.ktor.utils.io.peek
import io.ktor.utils.io.readUTF8Line
import io.ktor.utils.io.writeStringUtf8
import io.ktor.utils.io.core.ByteReadPacket
import io.ktor.utils.io.readRemaining
import kotlinx.coroutines.runBlocking
import kotlinx.io.Buffer
import kotlinx.io.IOException
import kotlinx.io.bytestring.decodeToString
import kotlinx.io.readByteArray
import kotlinx.io.readString
import kotlinx.io.unsafe.UnsafeBufferOperations
import kotlinx.io.writeString

fun main() = runBlocking {
    val packet = ByteReadPacket("packet".encodeToByteArray())
    println(packet.readByteArray().decodeToString())

    val source = ByteReadChannel("copy-bytes")
    val sink = ByteChannel(autoFlush = true)
    val copied = source.copyAndClose(sink)
    val copyData = sink.readRemaining().readByteArray().decodeToString()
    println("$copied:$copyData:${sink.isClosedForRead}")

    val lines = ByteReadChannel("café\r\n\n")
    println(lines.readUTF8Line())
    println(lines.readUTF8Line())
    println(lines.readUTF8Line() == null)

    val buffered = ByteChannel(autoFlush = true)
    buffered.writeStringUtf8("buffered\n")
    buffered.flushAndClose()
    println(buffered.readUTF8Line())
    println(buffered.readUTF8Line() == null)
    println(buffered.isClosedForRead)

    val cancelled = ByteChannel()
    cancelled.cancel(IOException("cancelled"))
    println("${cancelled.isClosedForRead}:${cancelled.closedCause?.message}")

    val byteStringChannel = ByteReadChannel("bytestring")
    val peeked = byteStringChannel.peek(10)
    println(peeked?.decodeToString())
    println(byteStringChannel.readRemaining().readByteArray().decodeToString())

    val unsafeBuffer = Buffer().apply { writeString("unsafe-data") }
    var borrowed = ""
    UnsafeBufferOperations.readFromHead(unsafeBuffer) { bytes, start, end ->
        borrowed = bytes.copyOfRange(start, end).decodeToString()
        0
    }
    println("$borrowed:${unsafeBuffer.readString()}")
}
