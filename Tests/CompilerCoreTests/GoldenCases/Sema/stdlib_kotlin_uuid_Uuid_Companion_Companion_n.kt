@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class, kotlin.time.ExperimentalTime::class)

package golden.sema

import kotlin.uuid.Uuid
import kotlin.time.Instant

fun useSizeConstants(): Int = Uuid.SIZE_BITS + Uuid.SIZE_BYTES

fun useNil(): Uuid = Uuid.NIL

fun useLexicalOrder(): Comparator<Uuid> = Uuid.LEXICAL_ORDER

fun useRandom(): Uuid = Uuid.random()

fun useGenerateV4(): Uuid = Uuid.generateV4()

fun useGenerateV7(): Uuid = Uuid.generateV7()

fun useGenerateV7NonMonotonicAt(instant: Instant): Uuid = Uuid.generateV7NonMonotonicAt(instant)

fun useFromLongs(msb: Long, lsb: Long): Uuid = Uuid.fromLongs(msb, lsb)

fun useFromULongs(msb: ULong, lsb: ULong): Uuid = Uuid.fromULongs(msb, lsb)

fun useFromByteArray(bytes: ByteArray): Uuid = Uuid.fromByteArray(bytes)

fun useFromUByteArray(bytes: UByteArray): Uuid = Uuid.fromUByteArray(bytes)

fun useParse(s: String): Uuid = Uuid.parse(s)

fun useParseOrNull(s: String): Uuid? = Uuid.parseOrNull(s)

fun useParseHex(s: String): Uuid = Uuid.parseHex(s)

fun useParseHexOrNull(s: String): Uuid? = Uuid.parseHexOrNull(s)

fun useParseHexDash(s: String): Uuid = Uuid.parseHexDash(s)

fun useParseHexDashOrNull(s: String): Uuid? = Uuid.parseHexDashOrNull(s)
