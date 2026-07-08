package kotlin.uuid

import kotlin.internal.KsSymbolName

// KSP-476: Uuid class + kotlin.uuid package fully migrated to Kotlin source.
// Only entropy (random), MD5 (nameUUIDFromBytes), opaque-box construction/
// reads (fromLongs / mostSignificantBits / leastSignificantBits),
// LEXICAL_ORDER (Comparator itable registration), and the java.util.UUID
// interop conversion (toKotlinUuid) remain native bridges. Parsing,
// formatting, bit extraction, and ByteArray packing are pure Kotlin built on
// top of those bridges.
//
// NOTE: the class declaration must come before any top-level declaration
// that references `Uuid` in its signature (return/parameter type) — forward
// references to a same-file class type from an earlier top-level signature
// don't resolve in this compiler yet, even though forward-referencing a
// function (calling something declared later) works fine.

/**
 * Represents a Universally Unique Identifier (UUID) as defined by RFC 9562.
 */
@kotlin.uuid.ExperimentalUuidApi
public class Uuid {

    public companion object {

        @kotlin.uuid.ExperimentalUuidApi
        public const val SIZE_BITS: Int = 128

        @kotlin.uuid.ExperimentalUuidApi
        public const val SIZE_BYTES: Int = 16

        @kotlin.uuid.ExperimentalUuidApi
        public val NIL: Uuid
            get() = __uuidFromLongs(0L, 0L)

        @kotlin.uuid.ExperimentalUuidApi
        public val LEXICAL_ORDER: Comparator<Uuid>
            get() = __uuidLexicalOrder()

        @kotlin.uuid.ExperimentalUuidApi
        public fun random(): Uuid = __uuidRandom()

        @kotlin.uuid.ExperimentalUuidApi
        public fun parse(uuidString: String): Uuid {
            val bits = parseUuidBitsOrNull(uuidString)
                ?: throw IllegalArgumentException("Invalid UUID string: $uuidString")
            return __uuidFromLongs(bits.first, bits.second)
        }

        @kotlin.uuid.ExperimentalUuidApi
        public fun parseOrNull(uuidString: String): Uuid? {
            val bits = parseUuidBitsOrNull(uuidString) ?: return null
            return __uuidFromLongs(bits.first, bits.second)
        }

        @kotlin.uuid.ExperimentalUuidApi
        public fun parseHex(hexString: String): Uuid {
            val bits = parseHexBitsOrNull(hexString)
                ?: throw IllegalArgumentException("Invalid UUID hex string: $hexString")
            return __uuidFromLongs(bits.first, bits.second)
        }

        @kotlin.uuid.ExperimentalUuidApi
        public fun parseHexOrNull(hexString: String): Uuid? {
            val bits = parseHexBitsOrNull(hexString) ?: return null
            return __uuidFromLongs(bits.first, bits.second)
        }

        @kotlin.uuid.ExperimentalUuidApi
        public fun parseHexDash(hexDashString: String): Uuid {
            val hex = hexFromHexDashStringOrNull(hexDashString)
                ?: throw IllegalArgumentException("Invalid UUID hex-and-dash string: $hexDashString")
            val bits = parseHexBitsOrNull(hex)
                ?: throw IllegalArgumentException("Invalid UUID hex-and-dash string: $hexDashString")
            return __uuidFromLongs(bits.first, bits.second)
        }

        @kotlin.uuid.ExperimentalUuidApi
        public fun parseHexDashOrNull(hexDashString: String): Uuid? {
            val hex = hexFromHexDashStringOrNull(hexDashString) ?: return null
            val bits = parseHexBitsOrNull(hex) ?: return null
            return __uuidFromLongs(bits.first, bits.second)
        }

        @kotlin.uuid.ExperimentalUuidApi
        public fun fromLongs(mostSignificantBits: Long, leastSignificantBits: Long): Uuid =
            __uuidFromLongs(mostSignificantBits, leastSignificantBits)

        @kotlin.uuid.ExperimentalUuidApi
        public fun fromByteArray(byteArray: ByteArray): Uuid {
            if (byteArray.size != 16) {
                throw IllegalArgumentException("byteArray.size must be 16, was ${byteArray.size}")
            }
            var msb = 0L
            var i = 0
            while (i < 8) {
                msb = (msb shl 8) or (byteArray[i].toLong() and 0xFFL)
                i += 1
            }
            var lsb = 0L
            i = 8
            while (i < 16) {
                lsb = (lsb shl 8) or (byteArray[i].toLong() and 0xFFL)
                i += 1
            }
            return __uuidFromLongs(msb, lsb)
        }

        @kotlin.uuid.ExperimentalUuidApi
        public fun nameUUIDFromBytes(name: ByteArray): Uuid = __uuidNameUUIDFromBytes(name)
    }

    @kotlin.uuid.ExperimentalUuidApi
    public val mostSignificantBits: Long
        get() = __uuidMostSignificantBits(this)

    @kotlin.uuid.ExperimentalUuidApi
    public val leastSignificantBits: Long
        get() = __uuidLeastSignificantBits(this)

    @kotlin.uuid.ExperimentalUuidApi
    public override fun toString(): String {
        val hex = mostSignificantBits.toHex16() + leastSignificantBits.toHex16()
        return hex.substring(0, 8) + "-" + hex.substring(8, 12) + "-" +
            hex.substring(12, 16) + "-" + hex.substring(16, 20) + "-" + hex.substring(20, 32)
    }

    @kotlin.uuid.ExperimentalUuidApi
    public fun toHexString(): String = mostSignificantBits.toHex16() + leastSignificantBits.toHex16()

    @kotlin.uuid.ExperimentalUuidApi
    public fun toLongs(): Pair<Long, Long> = Pair(mostSignificantBits, leastSignificantBits)

    @kotlin.uuid.ExperimentalUuidApi
    public fun toByteArray(): ByteArray {
        val result = ByteArray(16)
        val msb = mostSignificantBits
        val lsb = leastSignificantBits
        var i = 0
        while (i < 8) {
            result[i] = ((msb ushr (56 - i * 8)) and 0xFFL).toByte()
            i += 1
        }
        i = 0
        while (i < 8) {
            result[8 + i] = ((lsb ushr (56 - i * 8)) and 0xFFL).toByte()
            i += 1
        }
        return result
    }

    @kotlin.uuid.ExperimentalUuidApi
    public fun version(): Int = ((mostSignificantBits ushr 12) and 0xFL).toInt()

    @kotlin.uuid.ExperimentalUuidApi
    public fun variant(): Int {
        val top3 = (leastSignificantBits ushr 61) and 0x7L
        return when (top3) {
            0L, 1L, 2L, 3L -> 0
            4L, 5L -> 2
            6L -> 6
            else -> 7
        }
    }
}

// MARK: - Native bridges (irreducible: entropy / MD5 / opaque-box construction
// and reads / Comparator itable registration / java.util.UUID interop).

@kotlin.uuid.ExperimentalUuidApi
@KsSymbolName("__kk_uuid_random")
private external fun __uuidRandom(): Uuid

@kotlin.uuid.ExperimentalUuidApi
@KsSymbolName("__kk_uuid_fromLongs")
private external fun __uuidFromLongs(mostSignificantBits: Long, leastSignificantBits: Long): Uuid

@kotlin.uuid.ExperimentalUuidApi
@KsSymbolName("__kk_uuid_mostSignificantBits")
private external fun __uuidMostSignificantBits(receiver: Uuid): Long

@kotlin.uuid.ExperimentalUuidApi
@KsSymbolName("__kk_uuid_leastSignificantBits")
private external fun __uuidLeastSignificantBits(receiver: Uuid): Long

@kotlin.uuid.ExperimentalUuidApi
@KsSymbolName("__kk_uuid_nameUUIDFromBytes")
private external fun __uuidNameUUIDFromBytes(name: ByteArray): Uuid

@kotlin.uuid.ExperimentalUuidApi
@KsSymbolName("__kk_uuid_toKotlinUuid")
private external fun __uuidToKotlinUuid(receiver: java.util.UUID): Uuid

// LEXICAL_ORDER needs a Comparator<Uuid> instance. Multi-parameter SAM-conversion
// lambdas (`Comparator { a, b -> ... }`) do not resolve their lambda parameters
// correctly in this compiler yet, so the comparator itself stays a native bridge
// (itable-registered in Swift) rather than pure Kotlin.
@kotlin.uuid.ExperimentalUuidApi
@KsSymbolName("__kk_uuid_lexicalOrder")
private external fun __uuidLexicalOrder(): Comparator<Uuid>

// MARK: - Pure-Kotlin hex formatting / parsing / ByteArray packing helpers.

private val HEX_DIGITS: String = "0123456789abcdef"

private fun Long.toHex16(): String {
    val sb = StringBuilder(16)
    var i = 0
    while (i < 16) {
        val shift = (15 - i) * 4
        val nibble = ((this ushr shift) and 0xFL).toInt()
        sb.append(HEX_DIGITS[nibble])
        i += 1
    }
    return sb.toString()
}

private fun hexCharValue(c: Char): Int {
    if (c >= '0' && c <= '9') return c - '0'
    if (c >= 'a' && c <= 'f') return c - 'a' + 10
    if (c >= 'A' && c <= 'F') return c - 'A' + 10
    return -1
}

private fun isHexDigit(c: Char): Boolean = hexCharValue(c) >= 0

private fun parseHex16(hex: String): Long {
    var value = 0L
    var i = 0
    while (i < 16) {
        value = (value shl 4) or hexCharValue(hex[i]).toLong()
        i += 1
    }
    return value
}

private fun parseHexBitsOrNull(hex: String): Pair<Long, Long>? {
    if (hex.length != 32) return null
    var i = 0
    while (i < 32) {
        if (!isHexDigit(hex[i])) return null
        i += 1
    }
    val msb = parseHex16(hex.substring(0, 16))
    val lsb = parseHex16(hex.substring(16, 32))
    return Pair(msb, lsb)
}

private fun isHexDashSeparatorOffset(offset: Int): Boolean =
    offset == 8 || offset == 13 || offset == 18 || offset == 23

private fun hexFromHexDashStringOrNull(s: String): String? {
    if (s.length != 36) return null
    val sb = StringBuilder(32)
    var i = 0
    while (i < 36) {
        val c = s[i]
        if (isHexDashSeparatorOffset(i)) {
            if (c != '-') return null
        } else {
            if (!isHexDigit(c)) return null
            sb.append(c)
        }
        i += 1
    }
    return sb.toString()
}

private fun parseUuidBitsOrNull(s: String): Pair<Long, Long>? {
    if (s.length == 36) {
        val hex = hexFromHexDashStringOrNull(s) ?: return null
        return parseHexBitsOrNull(hex)
    }
    if (s.length == 32) {
        return parseHexBitsOrNull(s)
    }
    return null
}

@kotlin.uuid.ExperimentalUuidApi
private fun readUuidFromBytes(array: ByteArray, offset: Int): Uuid {
    if (offset < 0 || offset + 16 > array.size) {
        throw IndexOutOfBoundsException(
            "offset $offset is out of bounds for array of size ${array.size}"
        )
    }
    var msb = 0L
    var i = 0
    while (i < 8) {
        msb = (msb shl 8) or (array[offset + i].toLong() and 0xFFL)
        i += 1
    }
    var lsb = 0L
    i = 8
    while (i < 16) {
        lsb = (lsb shl 8) or (array[offset + i].toLong() and 0xFFL)
        i += 1
    }
    return __uuidFromLongs(msb, lsb)
}

// MARK: - Extension functions (kotlin.uuid package).

@kotlin.uuid.ExperimentalUuidApi
public fun java.util.UUID.toKotlinUuid(): Uuid = __uuidToKotlinUuid(this)

@kotlin.uuid.ExperimentalUuidApi
public fun ByteArray.getUuid(offset: Int): Uuid = readUuidFromBytes(this, offset)

@kotlin.uuid.ExperimentalUuidApi
public fun ByteArray.uuid(at: Int): Uuid = readUuidFromBytes(this, at)

@kotlin.uuid.ExperimentalUuidApi
public fun ByteArray.putUuid(at: Int, uuid: Uuid) {
    if (at < 0 || at + 16 > this.size) {
        throw IndexOutOfBoundsException(
            "at $at is out of bounds for array of size ${this.size}"
        )
    }
    val msb = uuid.mostSignificantBits
    val lsb = uuid.leastSignificantBits
    var i = 0
    while (i < 8) {
        this[at + i] = ((msb ushr (56 - i * 8)) and 0xFFL).toByte()
        i += 1
    }
    i = 0
    while (i < 8) {
        this[at + 8 + i] = ((lsb ushr (56 - i * 8)) and 0xFFL).toByte()
        i += 1
    }
}
