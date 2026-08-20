@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.Uuid

fun main() {
    val uuidStr = "550e8400-e29b-41d4-a716-446655440000"

    val fromULongs = Uuid.fromULongs(0x550e8400e29b41d4uL, 0xa716446655440000uL)
    println("fromULongs roundtrip: ${fromULongs.toString() == uuidStr}")

    val ubytes = fromULongs.toUByteArray()
    println("toUByteArray size: ${ubytes.size == 16}")

    val fromUBytes = Uuid.fromUByteArray(ubytes)
    println("fromUByteArray roundtrip: ${fromUBytes.toString() == uuidStr}")

    val nil = Uuid.NIL
    println("companion constants: ${Uuid.SIZE_BITS == 128 && Uuid.SIZE_BYTES == 16}")
    println("nil equals fromLongs(0,0): ${nil == Uuid.fromLongs(0L, 0L)}")
    println("nil.equals(fromLongs(0,0)): ${nil.equals(Uuid.fromLongs(0L, 0L))}")
    println("nil hashCode consistent: ${nil.hashCode() == Uuid.fromLongs(0L, 0L).hashCode()}")
    println("nil not equal to fromULongs: ${nil != fromULongs}")

    println("OK")
}
