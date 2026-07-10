@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.Uuid
import kotlin.uuid.putUuid
import kotlin.uuid.uuid

fun main() {
    val uuidStr = "550e8400-e29b-41d4-a716-446655440000"
    val original = Uuid.parse(uuidStr)

    // putUuid writes UUID bytes into ByteArray
    val buf = ByteArray(16)
    buf.putUuid(0, original)

    // uuid reads UUID back from ByteArray
    val restored = buf.uuid(0)
    println("roundtrip: ${restored.toString() == uuidStr}")

    // putUuid at non-zero offset
    val buf2 = ByteArray(20)
    buf2.putUuid(4, original)
    val restored2 = buf2.uuid(4)
    println("offset roundtrip: ${restored2.toString() == uuidStr}")

    // Bytes written by putUuid match toByteArray()
    val referenceBytes = original.toByteArray()
    var match = true
    for (i in 0 until 16) {
        if (buf[i] != referenceBytes[i]) {
            match = false
            break
        }
    }
    println("bytes match toByteArray: $match")

    // putUuid throws for a negative offset
    try {
        val small = ByteArray(16)
        small.putUuid(-1, original)
        println("putUuid negative offset: no exception thrown")
    } catch (e: IndexOutOfBoundsException) {
        println("putUuid negative offset: threw IndexOutOfBoundsException")
    }

    // putUuid throws when the array is too small to hold 16 bytes
    try {
        val tooSmall = ByteArray(10)
        tooSmall.putUuid(0, original)
        println("putUuid too-small array: no exception thrown")
    } catch (e: IndexOutOfBoundsException) {
        println("putUuid too-small array: threw IndexOutOfBoundsException")
    }

    // uuid(at:) throws when the offset runs past the end of the array
    try {
        val tooSmall = ByteArray(10)
        tooSmall.uuid(0)
        println("uuid too-small array: no exception thrown")
    } catch (e: IndexOutOfBoundsException) {
        println("uuid too-small array: threw IndexOutOfBoundsException")
    }

    println("OK")
}
