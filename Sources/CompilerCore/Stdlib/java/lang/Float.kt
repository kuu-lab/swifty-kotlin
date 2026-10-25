package java.lang

import kotlin.fromBits

public class Float private constructor() {
    public companion object {
        public val POSITIVE_INFINITY: kotlin.Float get() = kotlin.Float.POSITIVE_INFINITY
        public val NEGATIVE_INFINITY: kotlin.Float get() = kotlin.Float.NEGATIVE_INFINITY
        public val NaN: kotlin.Float get() = kotlin.Float.NaN
        public val MAX_VALUE: kotlin.Float get() = kotlin.Float.MAX_VALUE
        public val MIN_VALUE: kotlin.Float get() = kotlin.Float.MIN_VALUE
        public val MIN_NORMAL: kotlin.Float get() = 1.17549435E-38F
        public val MAX_EXPONENT: Int get() = 127
        public val MIN_EXPONENT: Int get() = -126
        public val SIZE: Int get() = 32
        public val BYTES: Int get() = 4

        public fun parseFloat(value: String): kotlin.Float = value.toFloat()

        public fun valueOf(value: String): kotlin.Float = parseFloat(value)

        public fun valueOf(value: kotlin.Float): kotlin.Float = value

        public fun toString(value: kotlin.Float): String = value.toString()

        public fun toHexString(value: kotlin.Float): String {
            val bits = value.toRawBits()
            val negative = bits < 0
            val sign = if (negative) "-" else ""
            val exponentBits = (bits ushr 23) and 0xFF
            val fractionBits = (bits and 0x7FFFFF) shl 1
            if (exponentBits == 0xFF) {
                return if (fractionBits != 0) "NaN" else sign + "Infinity"
            }
            if (exponentBits == 0 && fractionBits == 0) return sign + "0x0.0p0"

            val significand = if (exponentBits == 0) "0" else "1"
            val exponent = if (exponentBits == 0) -126 else exponentBits - 127
            val fraction = fractionBits.toString(16).padStart(6, '0').trimEnd('0').ifEmpty { "0" }
            return "${sign}0x$significand.$fraction" + "p" + exponent
        }

        public fun isNaN(value: kotlin.Float): kotlin.Boolean = value.isNaN()

        public fun isInfinite(value: kotlin.Float): kotlin.Boolean = value.isInfinite()

        public fun isFinite(value: kotlin.Float): kotlin.Boolean = value.isFinite()

        public fun compare(first: kotlin.Float, second: kotlin.Float): Int = first.compareTo(second)

        public fun hashCode(value: kotlin.Float): Int = value.toBits()

        public fun floatToIntBits(value: kotlin.Float): Int = value.toBits()

        public fun floatToRawIntBits(value: kotlin.Float): Int = value.toRawBits()

        public fun intBitsToFloat(bits: Int): kotlin.Float = fromBits(bits)

        public fun sum(first: kotlin.Float, second: kotlin.Float): kotlin.Float = first + second

        public fun min(first: kotlin.Float, second: kotlin.Float): kotlin.Float {
            if (first.isNaN()) return first
            if (second.isNaN()) return second
            if (first == 0.0F && second == 0.0F) {
                return if (first.toRawBits() < 0 || second.toRawBits() < 0) -0.0F else 0.0F
            }
            return if (first < second) first else second
        }

        public fun max(first: kotlin.Float, second: kotlin.Float): kotlin.Float {
            if (first.isNaN()) return first
            if (second.isNaN()) return second
            if (first == 0.0F && second == 0.0F) {
                return if (first.toRawBits() >= 0 || second.toRawBits() >= 0) 0.0F else -0.0F
            }
            return if (first > second) first else second
        }
    }
}
