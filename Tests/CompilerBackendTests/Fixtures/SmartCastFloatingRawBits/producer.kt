package rawbits

fun floatReceiver(value: Any?): Int = if (value is Float) value.toRawBits() else 17
fun doubleReceiver(value: Any?): Long = if (value is Double) value.toRawBits() else 17L

fun floatParameter(value: Float): Int = value.toRawBits()
fun doubleParameter(value: Double): Long = value.toRawBits()
fun floatArgument(value: Any): Int = if (value is Float) floatParameter(value) else 17
fun doubleArgument(value: Any): Long = if (value is Double) doubleParameter(value) else 17L

fun floatReturn(value: Any): Float = if (value is Float) value else 17.0f
fun doubleReturn(value: Any): Double = if (value is Double) value else 17.0
fun floatEarlyReturn(value: Any): Float {
    if (value is Float) return value
    return 17.0f
}
fun doubleEarlyReturn(value: Any): Double {
    if (value is Double) return value
    return 17.0
}
fun <T> identity(value: T): T = value
fun <T> genericFloatReceiver(value: T): Int = if (value is Float) value.toRawBits() else 17
fun <T> genericDoubleReceiver(value: T): Long = if (value is Double) value.toRawBits() else 17L
fun <T> genericFloatReturn(value: T): Float {
    if (value is Float) return value
    return 17.0f
}
fun <T> genericDoubleReturn(value: T): Double {
    if (value is Double) return value
    return 17.0
}

fun Float.rawBitsWith(mask: Int): Int = toRawBits() xor mask
fun Double.rawBitsWith(mask: Long): Long = toRawBits() xor mask
fun customFloatReceiver(value: Any): Int = if (value is Float) value.rawBitsWith(7) else 17
fun customDoubleReceiver(value: Any): Long = if (value is Double) value.rawBitsWith(7L) else 17L

fun nullableFloat(value: Float?): Int? = value?.toRawBits()
fun nullableDouble(value: Double?): Long? = value?.toRawBits()
fun checkedNullableFloat(value: Float?): Int = if (value != null) value.toRawBits() else 17
fun checkedNullableDouble(value: Double?): Long = if (value != null) value.toRawBits() else 17L
