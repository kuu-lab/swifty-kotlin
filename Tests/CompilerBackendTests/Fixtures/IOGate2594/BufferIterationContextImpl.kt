@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlinx.io.Buffer
import kotlinx.io.Segment
import kotlinx.io.UnsafeIoApi
import kotlinx.io.unsafe.BufferIterationContext
import kotlinx.io.unsafe.BufferIterationContextImpl
import kotlinx.io.unsafe.UnsafeBufferOperations

@OptIn(UnsafeIoApi::class)
fun main() {
    val buffer = Buffer()
    UnsafeBufferOperations.moveToTail(buffer, byteArrayOf(0x11, 0x12))
    UnsafeBufferOperations.moveToTail(buffer, byteArrayOf(0x21, 0x22))

    var callbackCount = 0
    var observations = ""
    UnsafeBufferOperations.iterate(buffer) { callbackContext, head ->
        callbackCount++
        val context: BufferIterationContext = BufferIterationContextImpl
        val repeatedContext: BufferIterationContext = BufferIterationContextImpl
        val first = checkNotNull(head)
        val second = checkNotNull(context.next(first))

        observations = listOf(
            "same-singleton=${context === repeatedContext}",
            "same-as-callback=${context === callbackContext}",
            "first-byte=${context.getUnchecked(first, 0).toInt()}",
            "next-byte=${context.getUnchecked(second, 0).toInt()}",
            "tail-next-is-null=${context.next(second) == null}"
        ).joinToString("\n")
    }

    check(callbackCount == 1)
    println(observations)
    println("callback-count=$callbackCount")
}
