package java.lang

public class Short private constructor() {
    public companion object {
        public val MAX_VALUE: kotlin.Short get() = 32767
        public val MIN_VALUE: kotlin.Short get() = -32768
        public val SIZE: Int get() = 16
        public val BYTES: Int get() = 2

        public fun parseShort(value: String): kotlin.Short = value.toShort()

        public fun parseShort(value: String, radix: Int): kotlin.Short = value.toShort(radix)

        public fun valueOf(value: String): kotlin.Short = parseShort(value)

        public fun valueOf(value: String, radix: Int): kotlin.Short = parseShort(value, radix)

        public fun valueOf(value: kotlin.Short): kotlin.Short = value

        public fun toString(value: kotlin.Short): String = value.toString()

        public fun hashCode(value: kotlin.Short): Int = value.toInt()

        public fun compare(first: kotlin.Short, second: kotlin.Short): Int = first.compareTo(second)

        public fun compareUnsigned(first: kotlin.Short, second: kotlin.Short): Int =
            (first.toInt() and 0xFFFF).compareTo(second.toInt() and 0xFFFF)

        public fun toUnsignedInt(value: kotlin.Short): Int = value.toInt() and 0xFFFF

        public fun toUnsignedLong(value: kotlin.Short): kotlin.Long = (value.toInt() and 0xFFFF).toLong()
    }
}
