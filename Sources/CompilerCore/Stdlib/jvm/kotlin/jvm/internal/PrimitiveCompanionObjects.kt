package kotlin.jvm.internal

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
