@file:OptIn(kotlinx.io.UnsafeIoApi::class)

package kuu2639unsafe

import kotlinx.io.Buffer
import kotlinx.io.readByteArray
import kotlinx.io.unsafe.UnsafeBufferOperations

private fun render(buffer: Buffer): String {
    if (buffer.size == 0L) return "empty"
    return buffer.readByteArray().joinToString(",")
}

private fun failure(block: () -> Unit): String = try {
    block()
    "none"
} catch (failure: Throwable) {
    failure::class.simpleName ?: "unknown"
}

public fun runMoveToTailRangeDefaultProbe() {
    val bytes = byteArrayOf(1, 2, 3, 4)

    val allDefaults = Buffer()
    UnsafeBufferOperations.moveToTail(allDefaults, bytes)
    println("all-defaults:" + render(allDefaults))

    val defaultStart = Buffer()
    UnsafeBufferOperations.moveToTail(defaultStart, bytes, endIndex = 3)
    println("default-start:" + render(defaultStart))

    val defaultEnd = Buffer()
    UnsafeBufferOperations.moveToTail(defaultEnd, bytes, startIndex = 2)
    println("default-end:" + render(defaultEnd))

    val explicitRange = Buffer()
    UnsafeBufferOperations.moveToTail(explicitRange, bytes, startIndex = 1, endIndex = 3)
    println("explicit-range:" + render(explicitRange))

    val emptyDefaultEnd = Buffer()
    UnsafeBufferOperations.moveToTail(emptyDefaultEnd, byteArrayOf(1, 2, 3), startIndex = 3)
    println("empty-default-end:" + render(emptyDefaultEnd))

    println("default-start-oob:" + failure {
        UnsafeBufferOperations.moveToTail(Buffer(), bytes, endIndex = 5)
    })
    println("explicit-negative-start:" + failure {
        UnsafeBufferOperations.moveToTail(Buffer(), bytes, startIndex = -1, endIndex = 1)
    })
    println("explicit-reversed:" + failure {
        UnsafeBufferOperations.moveToTail(Buffer(), bytes, startIndex = 2, endIndex = 1)
    })
}
