package kotlin.jvm.internal

public object StringCompanionObject

public object BooleanCompanionObject

public object ByteCompanionObject {
    public const val MIN_VALUE: Byte = -128
    public const val MAX_VALUE: Byte = 127
    public const val SIZE_BYTES: Int = 1
    public const val SIZE_BITS: Int = 8
}

public object ShortCompanionObject {
    public const val MIN_VALUE: Short = -32768
    public const val MAX_VALUE: Short = 32767
    public const val SIZE_BYTES: Int = 2
    public const val SIZE_BITS: Int = 16
}

public object CharCompanionObject {
    public const val MIN_VALUE: Char = '\u0000'
    public const val MAX_VALUE: Char = '\uFFFF'
    public const val MIN_HIGH_SURROGATE: Char = '\uD800'
    public const val MAX_HIGH_SURROGATE: Char = '\uDBFF'
    public const val MIN_LOW_SURROGATE: Char = '\uDC00'
    public const val MAX_LOW_SURROGATE: Char = '\uDFFF'
    public const val MIN_SURROGATE: Char = MIN_HIGH_SURROGATE
    public const val MAX_SURROGATE: Char = MAX_LOW_SURROGATE
    public const val SIZE_BYTES: Int = 2
    public const val SIZE_BITS: Int = 16
}

// JVM bytecode may load this singleton even when the Float constant is inlined.
public object FloatCompanionObject {
    public const val MIN_VALUE: Float = 1.4e-45f
    public const val MAX_VALUE: Float = 3.4028235e38f
    public const val POSITIVE_INFINITY: Float = 1.0f / 0.0f
    public const val NEGATIVE_INFINITY: Float = -1.0f / 0.0f
    public const val NaN: Float = 0.0f / 0.0f
    public const val SIZE_BYTES: Int = 4
    public const val SIZE_BITS: Int = 32

    public fun getMIN_VALUE(): Float = MIN_VALUE
    public fun getMAX_VALUE(): Float = MAX_VALUE
    public fun getPOSITIVE_INFINITY(): Float = POSITIVE_INFINITY
    public fun getNEGATIVE_INFINITY(): Float = NEGATIVE_INFINITY
    public fun getNaN(): Float = NaN
}

public object IntCompanionObject {
    public const val MIN_VALUE: Int = -2147483647 - 1
    public const val MAX_VALUE: Int = 2147483647
    public const val SIZE_BYTES: Int = 4
    public const val SIZE_BITS: Int = 32
}

public object LongCompanionObject {
    public const val MIN_VALUE: Long = -9223372036854775807L - 1L
    public const val MAX_VALUE: Long = 9223372036854775807L
    public const val SIZE_BYTES: Int = 8
    public const val SIZE_BITS: Int = 64
}

public object DoubleCompanionObject {
    public const val MIN_VALUE: Double = 4.9e-324
    public const val MAX_VALUE: Double = 1.7976931348623157e308
    public const val POSITIVE_INFINITY: Double = 1.0 / 0.0
    public const val NEGATIVE_INFINITY: Double = -1.0 / 0.0
    public const val NaN: Double = 0.0 / 0.0
    public const val SIZE_BYTES: Int = 8
    public const val SIZE_BITS: Int = 64

    public fun getMIN_VALUE(): Double = MIN_VALUE
    public fun getMAX_VALUE(): Double = MAX_VALUE
    public fun getPOSITIVE_INFINITY(): Double = POSITIVE_INFINITY
    public fun getNEGATIVE_INFINITY(): Double = NEGATIVE_INFINITY
    public fun getNaN(): Double = NaN
}
