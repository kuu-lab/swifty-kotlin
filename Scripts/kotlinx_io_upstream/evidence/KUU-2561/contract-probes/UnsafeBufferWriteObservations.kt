package io.gate.kuu2561

import kotlinx.io.*
import kotlinx.io.unsafe.UnsafeBufferOperations

private class ProbeException : RuntimeException()

@OptIn(UnsafeIoApi::class)
fun main() {
    val buffer = Buffer()
    var firstCallbackCount = 0
    val firstCount = UnsafeBufferOperations.writeToTail(buffer, 10) { context, segment ->
        firstCallbackCount += 1
        context.setUnchecked(segment, 0, 1)
        context.setUnchecked(segment, 1, 2, 3)
        context.setUnchecked(segment, 3, 4, 5, 6)
        context.setUnchecked(segment, 6, 7, 8, 9, 10)
        10
    }
    val firstBytes = buffer.readByteArray().contentToString()
    var overlapCallbackCount = 0
    val overlapCount = UnsafeBufferOperations.writeToTail(buffer, 4) { context, segment ->
        overlapCallbackCount += 1
        context.setUnchecked(segment, 0, 11, 11, 11, 11)
        context.setUnchecked(segment, 1, 10, 10, 10)
        context.setUnchecked(segment, 2, 9, 9)
        context.setUnchecked(segment, 3, 8)
        4
    }
    val overlapBytes = buffer.readByteArray().contentToString()
    println("multi=$firstCallbackCount/$firstCount:$firstBytes;overlap=$overlapCallbackCount/$overlapCount:$overlapBytes")

    val threeArgBuffer = Buffer()
    var threeArgCallbackCount = 0
    val threeArgException = try {
        UnsafeBufferOperations.writeToTail(threeArgBuffer, 2) { _, _, _ ->
            threeArgCallbackCount += 1
            throw ProbeException()
        }
        "NONE"
    } catch (_: ProbeException) {
        "ProbeException"
    }
    val threeArgExhausted = threeArgBuffer.exhausted()
    val twoArgBuffer = Buffer()
    var twoArgCallbackCount = 0
    val twoArgException = try {
        UnsafeBufferOperations.writeToTail(twoArgBuffer, 2) { _, _ ->
            twoArgCallbackCount += 1
            throw ProbeException()
        }
        "NONE"
    } catch (_: ProbeException) {
        "ProbeException"
    }
    println("reset=$threeArgCallbackCount/$threeArgException:$threeArgExhausted;$twoArgCallbackCount/$twoArgException:${twoArgBuffer.exhausted()}")

    val shortBuffer = Buffer()
    var shortCallbackCount = 0
    var callbackWriteCount = 0
    val reportedCount = UnsafeBufferOperations.writeToTail(shortBuffer, 42) { data, pos, limit ->
        shortCallbackCount += 1
        callbackWriteCount = limit - pos
        data.fill(0xab.toByte(), pos, limit)
        4
    }
    val committedSize = shortBuffer.size
    val readValue = shortBuffer.readUInt()
    println("short=$shortCallbackCount/$callbackWriteCount:$reportedCount:$committedSize:$readValue:${shortBuffer.exhausted()}")
}
