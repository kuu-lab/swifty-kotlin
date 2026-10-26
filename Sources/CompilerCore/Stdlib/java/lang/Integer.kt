package java.lang

public class Integer private constructor() {
    public companion object {
        public val MAX_VALUE: Int get() = 2147483647
        public val MIN_VALUE: Int get() = -2147483648
        public val SIZE: Int get() = 32
        public val BYTES: Int get() = 4

        public fun parseInt(value: String): Int = value.toInt()

        public fun parseInt(value: String, radix: Int): Int = value.toInt(radix)

        public fun parseUnsignedInt(value: String): Int = value.toUInt().toInt()

        public fun parseUnsignedInt(value: String, radix: Int): Int = value.toUInt(radix).toInt()

        public fun toString(value: Int): String = value.toString()

        public fun toString(value: Int, radix: Int): String = value.toString(radix)

        public fun toUnsignedString(value: Int): String = value.toUInt().toString(10)

        public fun toUnsignedString(value: Int, radix: Int): String = value.toUInt().toString(radix)

        public fun toHexString(value: Int): String = value.toUInt().toString(16)

        public fun toOctalString(value: Int): String = value.toUInt().toString(8)

        public fun toBinaryString(value: Int): String = value.toUInt().toString(2)

        public fun toUnsignedLong(value: Int): kotlin.Long = value.toLong() and 0xFFFFFFFFL

        public fun hashCode(value: Int): Int = value

        public fun compare(first: Int, second: Int): Int =
            if (first < second) -1 else if (first == second) 0 else 1

        public fun compareUnsigned(first: Int, second: Int): Int =
            first.toUInt().compareTo(second.toUInt())

        public fun signum(value: Int): Int =
            if (value < 0) -1 else if (value > 0) 1 else 0

        public fun highestOneBit(value: Int): Int = value.takeHighestOneBit()

        public fun lowestOneBit(value: Int): Int = value.takeLowestOneBit()

        public fun numberOfLeadingZeros(value: Int): Int = value.countLeadingZeroBits()

        public fun numberOfTrailingZeros(value: Int): Int = value.countTrailingZeroBits()

        public fun bitCount(value: Int): Int = value.countOneBits()

        public fun rotateLeft(value: Int, distance: Int): Int = value.rotateLeft(distance)

        public fun rotateRight(value: Int, distance: Int): Int = value.rotateRight(distance)

        public fun reverse(value: Int): Int {
            var result = value
            result = ((result ushr 1) and 0x55555555) or ((result and 0x55555555) shl 1)
            result = ((result ushr 2) and 0x33333333) or ((result and 0x33333333) shl 2)
            result = ((result ushr 4) and 0x0F0F0F0F) or ((result and 0x0F0F0F0F) shl 4)
            result = ((result ushr 8) and 0x00FF00FF) or ((result and 0x00FF00FF) shl 8)
            return (result ushr 16) or (result shl 16)
        }

        public fun reverseBytes(value: Int): Int =
            ((value ushr 24) and 0x000000FF) or
                ((value ushr 8) and 0x0000FF00) or
                ((value shl 8) and 0x00FF0000) or
                (value shl 24)

        public fun min(first: Int, second: Int): Int = if (first <= second) first else second

        public fun max(first: Int, second: Int): Int = if (first >= second) first else second

        public fun sum(first: Int, second: Int): Int = first + second
    }
}
