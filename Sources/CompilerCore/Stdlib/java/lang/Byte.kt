package java.lang

public class Byte private constructor() {
    public companion object {
        public val MAX_VALUE: kotlin.Byte get() = 127
        public val MIN_VALUE: kotlin.Byte get() = -128
        public val SIZE: Int get() = 8
        public val BYTES: Int get() = 1

        public fun parseByte(value: String): kotlin.Byte = value.toByte()

        public fun parseByte(value: String, radix: Int): kotlin.Byte = value.toByte(radix)

        public fun valueOf(value: String): kotlin.Byte = parseByte(value)

        public fun valueOf(value: String, radix: Int): kotlin.Byte = parseByte(value, radix)

        public fun valueOf(value: kotlin.Byte): kotlin.Byte = value

        public fun toString(value: kotlin.Byte): String = value.toString()

        public fun hashCode(value: kotlin.Byte): Int = value.toInt()

        public fun compare(first: kotlin.Byte, second: kotlin.Byte): Int = first.compareTo(second)

        public fun compareUnsigned(first: kotlin.Byte, second: kotlin.Byte): Int =
            (first.toInt() and 0xFF).compareTo(second.toInt() and 0xFF)

        public fun toUnsignedInt(value: kotlin.Byte): Int = value.toInt() and 0xFF

        public fun toUnsignedLong(value: kotlin.Byte): kotlin.Long = (value.toInt() and 0xFF).toLong()
    }
}
