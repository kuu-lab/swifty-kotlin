package java.math

public class MathContext(
    public val precision: Int,
    public val roundingMode: RoundingMode
) {
    init {
        if (precision < 0) {
            throw IllegalArgumentException("Digits < 0")
        }
    }

    public constructor(precision: Int) : this(precision, RoundingMode.HALF_UP)

    public companion object {
        public val UNLIMITED: MathContext = MathContext(0, RoundingMode.HALF_UP)
        public val DECIMAL32: MathContext = MathContext(7, RoundingMode.HALF_EVEN)
        public val DECIMAL64: MathContext = MathContext(16, RoundingMode.HALF_EVEN)
        public val DECIMAL128: MathContext = MathContext(34, RoundingMode.HALF_EVEN)
    }
}
