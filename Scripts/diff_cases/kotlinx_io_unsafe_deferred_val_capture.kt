@file:OptIn(kotlinx.io.UnsafeIoApi::class)

import kotlinx.io.Buffer
import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.toHexString
import kotlinx.io.unsafe.UnsafeBufferOperations
import kotlinx.io.unsafe.withData

fun main() {
    // Allocate something before the deferred val so it is not temporary(0).
    val buffer = Buffer().apply { writeByte(7) }
    val called: Boolean
    UnsafeBufferOperations.readFromHead(buffer) { _, _ ->
        called = true
        0
    }
    println(called)

    val captured: ByteString
    UnsafeBufferOperations.readFromHead(buffer) { _, _ ->
        captured = ByteString(1, 2)
        0
    }
    println(captured.toHexString())

    val outerCalled: Boolean
    UnsafeBufferOperations.iterate(buffer) { context, segment ->
        outerCalled = true
        val innerCalled: Boolean
        context.withData(segment!!) { _, _, _ -> innerCalled = true }
        println(innerCalled)
    }
    println(outerCalled)
    println(buffer.size)
}
