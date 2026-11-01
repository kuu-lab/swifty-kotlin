package java.util

/** A Java-compatible UUID with parsing and bit layout backed by Kotlin values. */
public class UUID(
    private val mostSigBits: Long,
    private val leastSigBits: Long,
) : Comparable<UUID> {
    public fun getMostSignificantBits(): Long = mostSigBits

    public fun getLeastSignificantBits(): Long = leastSigBits

    public fun version(): Int = ((mostSigBits ushr 12) and 0xFL).toInt()

    public fun variant(): Int {
        val topThreeBits = (leastSigBits ushr 61) and 0x7L
        return when (topThreeBits) {
            0b000L, 0b001L, 0b010L, 0b011L -> 0
            0b100L, 0b101L -> 2
            0b110L -> 6
            else -> 7
        }
    }

    override fun compareTo(other: UUID): Int {
        if (mostSigBits != other.mostSigBits) return if (mostSigBits < other.mostSigBits) -1 else 1
        if (leastSigBits != other.leastSigBits) return if (leastSigBits < other.leastSigBits) -1 else 1
        return 0
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is UUID) return false
        val that = other as UUID
        return mostSigBits == that.mostSigBits && leastSigBits == that.leastSigBits
    }

    override fun hashCode(): Int {
        val hilo = mostSigBits xor leastSigBits
        return ((hilo ushr 32) xor hilo).toInt()
    }

    override fun toString(): String {
        val result = StringBuilder()
        result.appendHex(mostSigBits ushr 32, 8)
        result.append('-')
        result.appendHex(mostSigBits ushr 16, 4)
        result.append('-')
        result.appendHex(mostSigBits, 4)
        result.append('-')
        result.appendHex(leastSigBits ushr 48, 4)
        result.append('-')
        result.appendHex(leastSigBits, 12)
        return result.toString()
    }

    public companion object {
        public fun randomUUID(): UUID {
            return kotlin.uuid.Uuid.random().toLongs { most, least -> UUID(most, least) }
        }

        public fun fromString(name: String): UUID {
            if (name.length != 36) throw IllegalArgumentException("Invalid UUID string: $name")
            var most = 0L
            var least = 0L
            var digitIndex = 0
            var index = 0
            while (index < name.length) {
                val character = name[index]
                if (index == 8 || index == 13 || index == 18 || index == 23) {
                    if (character != '-') throw IllegalArgumentException("Invalid UUID string: $name")
                } else {
                    val digit = uuidHexDigit(character)
                    if (digit < 0) throw IllegalArgumentException("Invalid UUID string: $name")
                    if (digitIndex < 16) {
                        most = (most shl 4) or digit.toLong()
                    } else {
                        least = (least shl 4) or digit.toLong()
                    }
                    digitIndex += 1
                }
                index += 1
            }
            return UUID(most, least)
        }
    }
}

private const val UUID_HEX_DIGITS: String = "0123456789abcdef"

private fun uuidHexDigit(character: Char): Int = when (character) {
    in '0'..'9' -> character.code - '0'.code
    in 'a'..'f' -> character.code - 'a'.code + 10
    in 'A'..'F' -> character.code - 'A'.code + 10
    else -> -1
}

private fun StringBuilder.appendHex(value: Long, digits: Int) {
    var shift = (digits - 1) * 4
    while (shift >= 0) {
        val digit = ((value ushr shift) and 0xFL).toInt()
        append(UUID_HEX_DIGITS[digit])
        shift -= 4
    }
}
