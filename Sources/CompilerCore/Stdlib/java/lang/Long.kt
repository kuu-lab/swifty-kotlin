package java.lang

public class Long private constructor() {
    public companion object {
        public val MAX_VALUE: kotlin.Long get() = kotlin.Long.MAX_VALUE
        public val MIN_VALUE: kotlin.Long get() = kotlin.Long.MIN_VALUE
        public val SIZE: Int get() = 64
        public val BYTES: Int get() = 8

        public fun parseLong(value: String): kotlin.Long = value.toLong()

        public fun parseLong(value: String, radix: Int): kotlin.Long =
            value.toLong(radix)

        public fun parseUnsignedLong(value: String): kotlin.Long =
            value.toULong().toLong()

        public fun parseUnsignedLong(value: String, radix: Int): kotlin.Long =
            value.toULong(radix).toLong()

        public fun toString(value: kotlin.Long): String = value.toString()

        public fun toString(value: kotlin.Long, radix: Int): String =
            value.toString(radix)

        public fun toUnsignedString(value: kotlin.Long): String = value.toULong().toString(10)

        public fun toUnsignedString(value: kotlin.Long, radix: Int): String =
            value.toULong().toString(radix)

        public fun toHexString(value: kotlin.Long): String = value.toULong().toString(16)

        public fun toOctalString(value: kotlin.Long): String = value.toULong().toString(8)

        public fun toBinaryString(value: kotlin.Long): String = value.toULong().toString(2)

        public fun compare(first: kotlin.Long, second: kotlin.Long): Int =
            if (first < second) -1 else if (first == second) 0 else 1

        public fun compareUnsigned(first: kotlin.Long, second: kotlin.Long): Int =
            first.toULong().compareTo(second.toULong())

        public fun hashCode(value: kotlin.Long): Int = (value xor (value ushr 32)).toInt()

        public fun signum(value: kotlin.Long): Int = if (value < 0L) -1 else if (value > 0L) 1 else 0

        public fun highestOneBit(value: kotlin.Long): kotlin.Long = value.takeHighestOneBit()

        public fun lowestOneBit(value: kotlin.Long): kotlin.Long = value.takeLowestOneBit()

        public fun numberOfLeadingZeros(value: kotlin.Long): Int =
            value.countLeadingZeroBits()

        public fun numberOfTrailingZeros(value: kotlin.Long): Int =
            value.countTrailingZeroBits()

        public fun bitCount(value: kotlin.Long): Int = value.countOneBits()

        public fun rotateLeft(value: kotlin.Long, distance: Int): kotlin.Long =
            value.rotateLeft(distance)

        public fun rotateRight(value: kotlin.Long, distance: Int): kotlin.Long =
            value.rotateRight(distance)

        public fun reverse(value: kotlin.Long): kotlin.Long {
            var result = value
            result = ((result ushr 1) and 0x5555555555555555L) or
                ((result and 0x5555555555555555L) shl 1)
            result = ((result ushr 2) and 0x3333333333333333L) or
                ((result and 0x3333333333333333L) shl 2)
            result = ((result ushr 4) and 0x0F0F0F0F0F0F0F0FL) or
                ((result and 0x0F0F0F0F0F0F0F0FL) shl 4)
            result = ((result ushr 8) and 0x00FF00FF00FF00FFL) or
                ((result and 0x00FF00FF00FF00FFL) shl 8)
            result = ((result ushr 16) and 0x0000FFFF0000FFFFL) or
                ((result and 0x0000FFFF0000FFFFL) shl 16)
            return (result ushr 32) or (result shl 32)
        }

        public fun reverseBytes(value: kotlin.Long): kotlin.Long =
            ((value ushr 56) and 0x00000000000000FFL) or
                ((value ushr 40) and 0x000000000000FF00L) or
                ((value ushr 24) and 0x0000000000FF0000L) or
                ((value ushr 8) and 0x00000000FF000000L) or
                ((value shl 8) and 0x000000FF00000000L) or
                ((value shl 24) and 0x0000FF0000000000L) or
                ((value shl 40) and 0x00FF000000000000L) or
                (value shl 56)

        public fun min(first: kotlin.Long, second: kotlin.Long): kotlin.Long =
            if (first <= second) first else second

        public fun max(first: kotlin.Long, second: kotlin.Long): kotlin.Long =
            if (first >= second) first else second

        public fun sum(first: kotlin.Long, second: kotlin.Long): kotlin.Long =
            first + second
    }
}
