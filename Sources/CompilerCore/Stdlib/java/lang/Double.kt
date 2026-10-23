package java.lang

public class Double private constructor() {
    public companion object {
        public val POSITIVE_INFINITY: kotlin.Double get() = kotlin.Double.POSITIVE_INFINITY
        public val NEGATIVE_INFINITY: kotlin.Double get() = kotlin.Double.NEGATIVE_INFINITY
        public val NaN: kotlin.Double get() = kotlin.Double.NaN
        public val MAX_VALUE: kotlin.Double get() = kotlin.Double.MAX_VALUE
        public val MIN_VALUE: kotlin.Double get() = kotlin.Double.MIN_VALUE
        public val MIN_NORMAL: kotlin.Double get() = 2.2250738585072014E-308
        public val MAX_EXPONENT: Int get() = 1023
        public val MIN_EXPONENT: Int get() = -1022
        public val SIZE: Int get() = 64
        public val BYTES: Int get() = 8

        public fun parseDouble(value: String): kotlin.Double = value.toDouble()

        public fun toString(value: kotlin.Double): String = value.toString()

        public fun isNaN(value: kotlin.Double): Boolean = value.isNaN()

        public fun isInfinite(value: kotlin.Double): Boolean = value.isInfinite()

        public fun isFinite(value: kotlin.Double): Boolean = value.isFinite()

        public fun compare(first: kotlin.Double, second: kotlin.Double): Int =
            first.compareTo(second)

        public fun signum(value: kotlin.Double): kotlin.Double =
            if (value.isNaN() || value == 0.0) value else if (value > 0.0) 1.0 else -1.0

        public fun sum(first: kotlin.Double, second: kotlin.Double): kotlin.Double =
            first + second

        public fun min(first: kotlin.Double, second: kotlin.Double): kotlin.Double {
            if (first.isNaN()) return first
            if (second.isNaN()) return second
            if (first == 0.0 && second == 0.0) {
                return if (first.toRawBits() < 0L || second.toRawBits() < 0L) -0.0 else 0.0
            }
            return if (first < second) first else second
        }

        public fun max(first: kotlin.Double, second: kotlin.Double): kotlin.Double {
            if (first.isNaN()) return first
            if (second.isNaN()) return second
            if (first == 0.0 && second == 0.0) {
                return if (first.toRawBits() >= 0L || second.toRawBits() >= 0L) 0.0 else -0.0
            }
            return if (first > second) first else second
        }
    }
}
