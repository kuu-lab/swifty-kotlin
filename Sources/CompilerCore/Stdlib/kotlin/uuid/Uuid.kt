package kotlin.uuid

@file:OptIn(ExperimentalUuidApi::class)

import kotlin.internal.KsSymbolName

private const val UUID_HEX_DIGITS: String = "0123456789abcdef"

/**
 * Represents a Universally Unique Identifier (UUID) as defined by RFC 9562.
 */
@ExperimentalUuidApi
public class Uuid private constructor(
    public val mostSignificantBits: Long,
    public val leastSignificantBits: Long,
) {
    public companion object {
        public const val SIZE_BITS: Int = 128
        public const val SIZE_BYTES: Int = 16

        public val NIL: Uuid = fromLongs(0L, 0L)

        public val LEXICAL_ORDER: Comparator<Uuid> = __kk_uuid_lexicalOrder()

        public fun random(): Uuid = __kk_uuid_random()

        public fun parse(uuidString: String): Uuid {
            val parsed = parseOrNull(uuidString)
            if (parsed == null) throw IllegalArgumentException("Invalid UUID string: $uuidString")
            return parsed!!
        }

        public fun parseOrNull(uuidString: String): Uuid? =
            parseStringOrNull(uuidString)

        public fun parseHex(hexString: String): Uuid {
            val parsed = parseHexOrNull(hexString)
            if (parsed == null) throw IllegalArgumentException("Invalid UUID hex string: $hexString")
            return parsed!!
        }

        public fun parseHexOrNull(hexString: String): Uuid? =
            parseHexBodyOrNull(hexString)

        public fun parseHexDash(hexDashString: String): Uuid {
            val hex = hexFromHexDashString(hexDashString)
            if (hex == null) throw IllegalArgumentException("Invalid UUID hex-and-dash string: $hexDashString")
            val parsed = parseHexBodyOrNull(hex!!)
            if (parsed == null) throw IllegalArgumentException("Invalid UUID hex-and-dash string: $hexDashString")
            return parsed!!
        }

        public fun parseHexDashOrNull(hexDashString: String): Uuid? {
            val hex = hexFromHexDashString(hexDashString)
            if (hex == null) return null
            return parseHexBodyOrNull(hex!!)
        }

        public fun nameUUIDFromBytes(name: ByteArray): Uuid =
            __kk_uuid_nameUUIDFromBytes(name)

        public fun fromLongs(mostSignificantBits: Long, leastSignificantBits: Long): Uuid =
            __kk_uuid_fromLongs(mostSignificantBits, leastSignificantBits)

        public fun fromByteArray(byteArray: ByteArray): Uuid {
            if (byteArray.size != SIZE_BYTES) {
                throw IllegalArgumentException("byteArray.size must be 16, was ${byteArray.size}")
            }
            var msb = 0L
            var lsb = 0L
            var i = 0
            while (i < 8) {
                msb = (msb shl 8) or (byteArray[i].toLong() and 0xffL)
                i += 1
            }
            while (i < 16) {
                lsb = (lsb shl 8) or (byteArray[i].toLong() and 0xffL)
                i += 1
            }
            return Uuid(msb, lsb)
        }

        private fun parseStringOrNull(uuidString: String): Uuid? {
            if (uuidString.length == 36) {
                val hex = hexFromHexDashString(uuidString)
                if (hex == null) return null
                return parseHexBodyOrNull(hex!!)
            }
            if (uuidString.length == 32) {
                return parseHexBodyOrNull(uuidString)
            }
            return null
        }

        private fun parseHexBodyOrNull(hex: String): Uuid? {
            if (hex.length != 32) return null
            var msb = 0L
            var lsb = 0L
            var i = 0
            while (i < 16) {
                val digit = hexDigit(hex[i])
                if (digit < 0) return null
                msb = (msb shl 4) or digit.toLong()
                i += 1
            }
            while (i < 32) {
                val digit = hexDigit(hex[i])
                if (digit < 0) return null
                lsb = (lsb shl 4) or digit.toLong()
                i += 1
            }
            return Uuid(msb, lsb)
        }

        private fun hexFromHexDashString(hexDashString: String): String? {
            if (hexDashString.length != 36) return null
            val sb = StringBuilder()
            var i = 0
            while (i < 36) {
                val ch = hexDashString[i]
                if (i == 8 || i == 13 || i == 18 || i == 23) {
                    if (ch != '-') return null
                } else {
                    if (hexDigit(ch) < 0) return null
                    sb.append(ch)
                }
                i += 1
            }
            return sb.toString()
        }

        private fun hexDigit(ch: Char): Int {
            if (ch >= '0' && ch <= '9') return ch.code - '0'.code
            if (ch >= 'a' && ch <= 'f') return ch.code - 'a'.code + 10
            if (ch >= 'A' && ch <= 'F') return ch.code - 'A'.code + 10
            return -1
        }

    }

    public override fun toString(): String {
        val sb = StringBuilder()
        val msb = mostSignificantBits
        val lsb = leastSignificantBits
        appendHex(sb, msb ushr 32, 8)
        sb.append('-')
        appendHex(sb, msb ushr 16, 4)
        sb.append('-')
        appendHex(sb, msb, 4)
        sb.append('-')
        appendHex(sb, lsb ushr 48, 4)
        sb.append('-')
        appendHex(sb, lsb, 12)
        return sb.toString()
    }

    public fun toHexString(): String {
        val sb = StringBuilder()
        appendHex(sb, mostSignificantBits, 16)
        appendHex(sb, leastSignificantBits, 16)
        return sb.toString()
    }

    public fun toLongs(): Pair<Long, Long> =
        Pair(mostSignificantBits, leastSignificantBits)

    public fun toByteArray(): ByteArray {
        val bytes = ByteArray(SIZE_BYTES) { 0 }
        val msb = mostSignificantBits
        val lsb = leastSignificantBits
        var i = 0
        while (i < 8) {
            bytes[i] = ((msb ushr (56 - i * 8)) and 0xffL).toByte()
            i += 1
        }
        while (i < 16) {
            bytes[i] = ((lsb ushr (56 - (i - 8) * 8)) and 0xffL).toByte()
            i += 1
        }
        return bytes
    }

    public fun version(): Int =
        ((mostSignificantBits ushr 12) and 0x0fL).toInt()

    public fun variant(): Int {
        val topThreeBits = ((leastSignificantBits ushr 61) and 0x07L).toInt()
        if (topThreeBits < 4) return 0
        if (topThreeBits < 6) return 2
        if (topThreeBits == 6) return 6
        return 7
    }

    private fun appendHex(sb: StringBuilder, value: Long, digits: Int) {
        var shift = (digits - 1) * 4
        while (shift >= 0) {
            val digit = ((value ushr shift) and 0x0fL).toInt()
            sb.append(UUID_HEX_DIGITS[digit])
            shift -= 4
        }
    }
}

@KsSymbolName("__kk_uuid_random")
private external fun __kk_uuid_random(): Uuid

@KsSymbolName("__kk_uuid_nameUUIDFromBytes")
private external fun __kk_uuid_nameUUIDFromBytes(name: ByteArray): Uuid

@KsSymbolName("__kk_uuid_fromLongs")
private external fun __kk_uuid_fromLongs(mostSignificantBits: Long, leastSignificantBits: Long): Uuid

@KsSymbolName("__kk_uuid_lexicalOrder")
private external fun __kk_uuid_lexicalOrder(): Comparator<Uuid>

// java.util.UUID interop needs a native bridge to read a foreign UUID
// representation; every other kotlin.uuid extension below is pure Kotlin
// built on top of Uuid's own mostSignificantBits/leastSignificantBits/fromLongs.
@KsSymbolName("__kk_uuid_toKotlinUuid")
private external fun __kk_uuid_toKotlinUuid(receiver: java.util.UUID): Uuid

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
    return Uuid.fromLongs(msb, lsb)
}

@kotlin.uuid.ExperimentalUuidApi
public fun java.util.UUID.toKotlinUuid(): Uuid = __kk_uuid_toKotlinUuid(this)

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
