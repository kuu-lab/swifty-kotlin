@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class)

package golden.sema

import kotlin.uuid.Uuid

fun uuidCompanionConstants(): Int = Uuid.SIZE_BITS + Uuid.SIZE_BYTES

fun uuidCompanionNil(): Uuid = Uuid.NIL

fun uuidCompanionRandom(): Uuid = Uuid.random()

fun uuidCompanionFromLongs(msb: Long, lsb: Long): Uuid = Uuid.fromLongs(msb, lsb)

fun uuidCompanionFromULongs(msb: ULong, lsb: ULong): Uuid = Uuid.fromULongs(msb, lsb)

fun uuidCompanionFromByteArray(bytes: ByteArray): Uuid = Uuid.fromByteArray(bytes)

fun uuidCompanionFromUByteArray(bytes: UByteArray): Uuid = Uuid.fromUByteArray(bytes)

fun uuidCompanionParse(text: String): Uuid = Uuid.parse(text)

fun uuidCompanionParseOrNull(text: String): Uuid? = Uuid.parseOrNull(text)

fun uuidCompanionParseHex(text: String): Uuid = Uuid.parseHex(text)

fun uuidCompanionParseHexOrNull(text: String): Uuid? = Uuid.parseHexOrNull(text)

fun uuidCompanionNilEquality(): Boolean = Uuid.NIL == Uuid.fromLongs(0L, 0L)

fun uuidCompanionNilHashCode(): Int = Uuid.NIL.hashCode()
