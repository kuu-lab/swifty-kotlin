@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

import kotlin.uuid.Uuid
import kotlin.time.Instant

// LEXICAL_ORDER is intentionally not exercised here: it is
// @DeprecatedSinceKotlin(errorSince = "2.4"), so referencing it fails to
// compile against the real kotlinc 2.4+ reference used by this diff harness.
// It is still covered by the Sema golden test, since kswiftc targets Kotlin
// 2.3.10 semantics, where the same reference is only a deprecation warning.
fun main() {
    println("size constants: ${Uuid.SIZE_BITS == 128 && Uuid.SIZE_BYTES == 16}")
    println("nil: ${Uuid.NIL.toString() == "00000000-0000-0000-0000-000000000000"}")

    val r = Uuid.random()
    val rBytes = r.toByteArray()
    println("random version=4: ${((rBytes[6].toInt() and 0xFF) ushr 4) == 4}")
    println("random variant=2: ${((rBytes[8].toInt() and 0xFF) ushr 6) == 2}")

    val v4 = Uuid.generateV4()
    val v4Bytes = v4.toByteArray()
    println("generateV4 version=4: ${((v4Bytes[6].toInt() and 0xFF) ushr 4) == 4}")

    val v7 = Uuid.generateV7()
    val v7Bytes = v7.toByteArray()
    println("generateV7 version=7: ${((v7Bytes[6].toInt() and 0xFF) ushr 4) == 7}")
    println("generateV7 variant=2: ${((v7Bytes[8].toInt() and 0xFF) ushr 6) == 2}")

    val v7b = Uuid.generateV7()
    println("two generateV7 calls differ: ${v7.toString() != v7b.toString()}")

    val fixedMs = 1700000000000L
    val fixedInstant = Instant.fromEpochMilliseconds(fixedMs)
    val v7at = Uuid.generateV7NonMonotonicAt(fixedInstant)
    val v7atBytes = v7at.toByteArray()
    println("generateV7NonMonotonicAt version=7: ${((v7atBytes[6].toInt() and 0xFF) ushr 4) == 7}")
    println("generateV7NonMonotonicAt variant=2: ${((v7atBytes[8].toInt() and 0xFF) ushr 6) == 2}")

    // The 48-bit unix_ts_ms prefix occupies exactly the first 6 bytes, so it
    // can be reconstructed and compared against fixedMs deterministically.
    var decodedMs = 0L
    var i = 0
    while (i < 6) {
        decodedMs = (decodedMs shl 8) or (v7atBytes[i].toLong() and 0xFFL)
        i += 1
    }
    println("generateV7NonMonotonicAt timestamp round trip: ${decodedMs == fixedMs}")

    val v7at2 = Uuid.generateV7NonMonotonicAt(fixedInstant)
    println("two generateV7NonMonotonicAt(same instant) differ: ${v7at.toString() != v7at2.toString()}")

    val uuidStr = "01020304-0506-0708-090a-0b0c0d0e0f10"
    val viaLongs = Uuid.fromLongs(0x0102030405060708L, 0x090a0b0c0d0e0f10L)
    println("fromLongs: ${viaLongs.toString() == uuidStr}")

    val viaULongs = Uuid.fromULongs(0x0102030405060708uL, 0x090a0b0c0d0e0f10uL)
    println("fromULongs: ${viaULongs.toString() == uuidStr}")

    val bytes = viaLongs.toByteArray()
    val viaBytes = Uuid.fromByteArray(bytes)
    println("fromByteArray: ${viaBytes.toString() == uuidStr}")

    val ubytes = viaLongs.toUByteArray()
    val viaUBytes = Uuid.fromUByteArray(ubytes)
    println("fromUByteArray: ${viaUBytes.toString() == uuidStr}")

    println("parse: ${Uuid.parse(uuidStr).toString() == uuidStr}")
    println("parseOrNull valid: ${Uuid.parseOrNull(uuidStr)?.toString() == uuidStr}")
    println("parseOrNull invalid: ${Uuid.parseOrNull("not-a-uuid") == null}")

    val hexStr = "0102030405060708090a0b0c0d0e0f10"
    println("parseHex: ${Uuid.parseHex(hexStr).toString() == uuidStr}")
    println("parseHexOrNull valid: ${Uuid.parseHexOrNull(hexStr)?.toString() == uuidStr}")
    println("parseHexOrNull invalid: ${Uuid.parseHexOrNull("zz") == null}")

    println("parseHexDash: ${Uuid.parseHexDash(uuidStr).toString() == uuidStr}")
    println("parseHexDashOrNull valid: ${Uuid.parseHexDashOrNull(uuidStr)?.toString() == uuidStr}")
    println("parseHexDashOrNull invalid: ${Uuid.parseHexDashOrNull(hexStr) == null}")

    println("OK")
}
