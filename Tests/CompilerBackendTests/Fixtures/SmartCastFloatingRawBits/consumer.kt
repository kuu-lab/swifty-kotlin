import rawbits.*

fun checkFloat(value: Float, bits: Int) {
    val erased: Any = value
    println(value.toRawBits() == bits)
    println(floatReceiver(erased) == bits)
    println(floatArgument(erased) == bits)
    println(floatReturn(erased).toRawBits() == bits)
    println(floatEarlyReturn(erased).toRawBits() == bits)
    println(identity(value).toRawBits() == bits)
    println(genericFloatReceiver(value) == bits)
    println(genericFloatReturn(value).toRawBits() == bits)
    println(customFloatReceiver(erased) == (bits xor 7))
    println(nullableFloat(value) == bits)
    println(checkedNullableFloat(value) == bits)
}

fun checkDouble(value: Double, bits: Long) {
    val erased: Any = value
    println(value.toRawBits() == bits)
    println(doubleReceiver(erased) == bits)
    println(doubleArgument(erased) == bits)
    println(doubleReturn(erased).toRawBits() == bits)
    println(doubleEarlyReturn(erased).toRawBits() == bits)
    println(identity(value).toRawBits() == bits)
    println(genericDoubleReceiver(value) == bits)
    println(genericDoubleReturn(value).toRawBits() == bits)
    println(customDoubleReceiver(erased) == (bits xor 7L))
    println(nullableDouble(value) == bits)
    println(checkedNullableDouble(value) == bits)
}

fun main() {
    checkFloat(1.25f, 1067450368)
    checkFloat(0.0f, 0)
    checkFloat(-0.0f, Int.MIN_VALUE)
    checkFloat(Float.fromBits(0x7FC12345), 0x7FC12345)
    checkDouble(1.25, 4608308318706860032L)
    checkDouble(0.0, 0L)
    checkDouble(-0.0, Long.MIN_VALUE)
    checkDouble(Double.fromBits(0x7FF8000000001234L), 0x7FF8000000001234L)
    println(floatReceiver(null) == 17)
    println(doubleReceiver(null) == 17L)
    println(nullableFloat(null) == null)
    println(nullableDouble(null) == null)
    println(checkedNullableFloat(null) == 17)
    println(checkedNullableDouble(null) == 17L)
}
