// SKIP-DIFF (DEBT-DIFF-001): uses KSwiftK UUID APIs that are not available in the kotlinc JVM reference.
@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.Uuid

fun main() {
    val uuid1 = Uuid.random()
    val uuid2 = Uuid.random()
    println("uuid1 created: ${uuid1.toString().length == 36}")
    println("uuid2 created: ${uuid2.toString().length == 36}")
    println("uuids different: ${uuid1.toString() != uuid2.toString()}")
    println("uuid1 version: ${uuid1.version() == 4}")
    println("uuid1 variant: ${uuid1.variant() == 2}")

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

    val longs = parsed.toLongs()
    val fromLongs = Uuid.fromLongs(longs.first, longs.second)
    println("fromLongs roundtrip: ${fromLongs.toString() == uuidStr}")
    println("most bits match: ${parsed.mostSignificantBits == longs.first}")
    println("least bits match: ${parsed.leastSignificantBits == longs.second}")
    println("known version: ${parsed.version() == 4}")
    println("known variant: ${parsed.variant() == 2}")

    val bytes = parsed.toByteArray()
    println("byteArray size: ${bytes.size == 16}")
    val fromBytes = Uuid.fromByteArray(bytes)
    println("fromByteArray roundtrip: ${fromBytes.toString() == uuidStr}")

    val nil = Uuid.NIL
    println("nil string: ${nil.toString() == nilStr}")
    println("constants: ${Uuid.SIZE_BITS == 128 && Uuid.SIZE_BYTES == 16}")
    println("lexical order equal: ${Uuid.LEXICAL_ORDER.compare(parsed, fromBytes) == 0}")

    val named = Uuid.nameUUIDFromBytes(byteArrayOf(104, 101, 108, 108, 111))
    println("name uuid version: ${named.version() == 3}")
    println("name uuid variant: ${named.variant() == 2}")

    println("OK")
}
