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

        public val LEXICAL_ORDER: Comparator<Uuid> = object : Comparator<Uuid> {
            public override fun compare(a: Uuid, b: Uuid): Int {
                val msbCompare = compareUnsignedLongs(a.mostSignificantBits, b.mostSignificantBits)
                if (msbCompare != 0) return msbCompare
                return compareUnsignedLongs(a.leastSignificantBits, b.leastSignificantBits)
            }
        }

        public fun random(): Uuid = __kk_uuid_random()

        public fun parse(uuidString: String): Uuid =
            parseOrNull(uuidString) ?: throw IllegalArgumentException("Invalid UUID string: $uuidString")

        public fun parseOrNull(uuidString: String): Uuid? =
            parseStringOrNull(uuidString)

        public fun parseHex(hexString: String): Uuid =
            parseHexOrNull(hexString) ?: throw IllegalArgumentException("Invalid UUID hex string: $hexString")

        public fun parseHexOrNull(hexString: String): Uuid? =
            parseHexBodyOrNull(hexString)

        public fun parseHexDash(hexDashString: String): Uuid {
            val hex = hexFromHexDashString(hexDashString)
                ?: throw IllegalArgumentException("Invalid UUID hex-and-dash string: $hexDashString")
            return parseHexBodyOrNull(hex)
                ?: throw IllegalArgumentException("Invalid UUID hex-and-dash string: $hexDashString")
        }

        public fun parseHexDashOrNull(hexDashString: String): Uuid? {
            val hex = hexFromHexDashString(hexDashString) ?: return null
            return parseHexBodyOrNull(hex)
        }

        public fun nameUUIDFromBytes(name: ByteArray): Uuid =
            __kk_uuid_nameUUIDFromBytes(name)

        public fun fromLongs(mostSignificantBits: Long, leastSignificantBits: Long): Uuid =
            Uuid(mostSignificantBits, leastSignificantBits)

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
                val hex = hexFromHexDashString(uuidString) ?: return null
                return parseHexBodyOrNull(hex)
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
                val digit = hexDigitOrNull(hex[i]) ?: return null
                msb = (msb shl 4) or digit.toLong()
                i += 1
            }
            while (i < 32) {
                val digit = hexDigitOrNull(hex[i]) ?: return null
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
                    if (hexDigitOrNull(ch) == null) return null
                    sb.append(ch)
                }
                i += 1
            }
            return sb.toString()
        }

        private fun hexDigitOrNull(ch: Char): Int? =
            ch.digitToIntOrNull(16)

        private fun compareUnsignedLongs(a: Long, b: Long): Int {
            if (a == b) return 0
            val aNegative = a < 0L
            val bNegative = b < 0L
            if (aNegative != bNegative) {
                return if (aNegative) 1 else -1
            }
            return if (a < b) -1 else 1
        }
    }

    public override fun toString(): String {
        val sb = StringBuilder()
        appendHex(sb, mostSignificantBits ushr 32, 8)
        sb.append('-')
        appendHex(sb, mostSignificantBits ushr 16, 4)
        sb.append('-')
        appendHex(sb, mostSignificantBits, 4)
        sb.append('-')
        appendHex(sb, leastSignificantBits ushr 48, 4)
        sb.append('-')
        appendHex(sb, leastSignificantBits, 12)
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
        val bytes = ByteArray(SIZE_BYTES)
        var i = 0
        while (i < 8) {
            bytes[i] = ((mostSignificantBits ushr (56 - i * 8)) and 0xffL).toInt()
            i += 1
        }
        while (i < 16) {
            bytes[i] = ((leastSignificantBits ushr (56 - (i - 8) * 8)) and 0xffL).toInt()
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
