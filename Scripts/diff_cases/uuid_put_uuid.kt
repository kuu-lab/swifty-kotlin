@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.Uuid
import kotlin.uuid.getUuid
import kotlin.uuid.putUuid
import java.nio.ByteBuffer

fun main() {
    val uuidStr = "550e8400-e29b-41d4-a716-446655440000"
    val original = Uuid.parse(uuidStr)

    // putUuid writes UUID bytes into ByteBuffer at the current position
    val buf = ByteBuffer.allocate(16)
    buf.putUuid(original)
    buf.position(0)
    val restored = buf.getUuid()
    println("roundtrip: ${restored.toString() == uuidStr}")

    // putUuid/getUuid at a non-zero index
    val buf2 = ByteBuffer.allocate(20)
    buf2.putUuid(4, original)
    val restored2 = buf2.getUuid(4)
    println("offset roundtrip: ${restored2.toString() == uuidStr}")

    // Bytes written by putUuid match toByteArray()
    val referenceBytes = original.toByteArray()
    val writtenBytes = buf.array()
    var match = true
    for (i in 0 until 16) {
        if (writtenBytes[i] != referenceBytes[i]) {
            match = false
            break
        }
    }
    println("bytes match toByteArray: $match")

    // putUuid throws for a negative index
    try {
        val small = ByteBuffer.allocate(16)
        small.putUuid(-1, original)
        println("putUuid negative offset: no exception thrown")
    } catch (e: IndexOutOfBoundsException) {
        println("putUuid negative offset: threw IndexOutOfBoundsException")
    }

    // putUuid throws when the buffer is too small to hold 16 bytes
    try {
        val tooSmall = ByteBuffer.allocate(10)
        tooSmall.putUuid(0, original)
        println("putUuid too-small buffer: no exception thrown")
    } catch (e: IndexOutOfBoundsException) {
        println("putUuid too-small buffer: threw IndexOutOfBoundsException")
    }

    // getUuid(index) throws when the index runs past the end of the buffer
    try {
        val tooSmall = ByteBuffer.allocate(10)
        tooSmall.getUuid(0)
        println("getUuid too-small buffer: no exception thrown")
    } catch (e: IndexOutOfBoundsException) {
        println("getUuid too-small buffer: threw IndexOutOfBoundsException")
    }

    println("OK")
}
