@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.Uuid

fun main() {
    val uuid1 = Uuid.random()
    val uuid2 = Uuid.random()
    println("uuid1 created: ${uuid1.toString().length == 36}")
    println("uuid2 created: ${uuid2.toString().length == 36}")
    println("uuids different: ${uuid1.toString() != uuid2.toString()}")

    val uuidStr = "550e8400-e29b-41d4-a716-446655440000"
    val uuidHex = "550e8400e29b41d4a716446655440000"
    val invalidUuid = "not-a-uuid"
    val invalidHex = "xyz"
    val nilStr = "00000000-0000-0000-0000-000000000000"
    val parsed = Uuid.parse(uuidStr)
    println("parse roundtrip: ${parsed.toString() == uuidStr}")
    println("parseOrNull valid: ${Uuid.parseOrNull(uuidStr)?.toString() == uuidStr}")
    println("parseOrNull invalid: ${Uuid.parseOrNull(invalidUuid) == null}")
    println("parseHex roundtrip: ${Uuid.parseHex(uuidHex).toString() == uuidStr}")
    println("parseHexOrNull valid: ${Uuid.parseHexOrNull(uuidHex)?.toString() == uuidStr}")
    println("parseHexOrNull invalid: ${Uuid.parseHexOrNull(invalidHex) == null}")
    println("parseHexDash roundtrip: ${Uuid.parseHexDash(uuidStr).toString() == uuidStr}")
    println("parseHexDashOrNull valid: ${Uuid.parseHexDashOrNull(uuidStr)?.toString() == uuidStr}")
    println("parseHexDashOrNull invalid: ${Uuid.parseHexDashOrNull(uuidHex) == null}")
    println("toHexString: ${parsed.toHexString() == uuidHex}")

    val fromLongs = Uuid.fromLongs(0x550e8400e29b41d4L, 0xa716446655440000uL.toLong())
    println("fromLongs roundtrip: ${fromLongs.toString() == uuidStr}")

    val bytes = parsed.toByteArray()
    println("byteArray size: ${bytes.size == 16}")
    println("known version: ${((bytes[6].toInt() and 0xFF) ushr 4) == 4}")
    println("known variant: ${((bytes[8].toInt() and 0xFF) ushr 6) == 2}")
    val fromBytes = Uuid.fromByteArray(bytes)
    println("fromByteArray roundtrip: ${fromBytes.toString() == uuidStr}")

    val nil = Uuid.NIL
    println("nil string: ${nil.toString() == nilStr}")
    println("constants: ${Uuid.SIZE_BITS == 128 && Uuid.SIZE_BYTES == 16}")

    println("OK")
}
