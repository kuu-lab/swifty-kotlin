class Label {
    override fun toString(): String = "label"
}

fun main() {
    val boolToString: (Boolean) -> String = Boolean::toString
    println(boolToString(true))
    println(boolToString(false))
    val sameReference: (Boolean) -> String = Boolean::toString
    println(boolToString == sameReference)
    println(boolToString is kotlin.reflect.KFunction<*>)
    val reflected = boolToString as kotlin.reflect.KFunction<*>
    println(reflected.name)
    println(reflected.call(true))
    println(reflected.call(false))
    val inferred = Boolean::toString
    println(inferred(true))
    println(inferred(false))
    val boundTrue: () -> String = true::toString
    val boundFalse: () -> String = false::toString
    println(boundTrue())
    println(boundFalse())
    println(true.toString())
    println(false.toString())

    val nullableToString: (Boolean?) -> String = Boolean?::toString
    println(nullableToString(null))
    println(nullableToString(true))
    println(nullableToString(false))
    val nullableValue: Boolean? = null
    val nullableBound: () -> String = nullableValue::toString
    println(nullableBound())
    val nullableTrue: Boolean? = true
    val nullableFalse: Boolean? = false
    val nullableBoundTrue: () -> String = nullableTrue::toString
    val nullableBoundFalse: () -> String = nullableFalse::toString
    println(nullableBoundTrue())
    println(nullableBoundFalse())

    val erased: Any = boolToString
    val restored = erased as (Boolean) -> String
    println(restored(true))
    println(restored(false))
    val optional: ((Boolean) -> String)? = boolToString
    println(optional?.invoke(true))
    println(optional?.invoke(false))
    println(listOf(true, false).map(Boolean::toString))

    val anyToString: (Any) -> String = Any::toString
    println(anyToString(Label()))
    val boundAny: () -> String = (true as Any)::toString
    println(boundAny())
    val intToString: (Int) -> String = Int::toString
    val longToString: (Long) -> String = Long::toString
    val charToString: (Char) -> String = Char::toString
    val stringToString: (String) -> String = String::toString
    println(intToString(1))
    println(longToString(123L))
    println(charToString('A'))
    println(stringToString("text"))

    val boundChar: () -> String = 'Z'::toString
    val nullableCharToString: (Char?) -> String = Char?::toString
    println(boundChar())
    println('A'.toString())
    println(nullableCharToString(null))
    println(nullableCharToString('A'))
    println((charToString as kotlin.reflect.KFunction<*>).call('B'))

    val floatToString: (Float) -> String = Float::toString
    val boundFloat: () -> String = (1.5f)::toString
    val nullableFloatToString: (Float?) -> String = Float?::toString
    println(floatToString(1.5f))
    println(floatToString(-0.0f))
    println(boundFloat())
    println(1.5f.toString())
    println(nullableFloatToString(null))
    println(nullableFloatToString(-0.0f))
    println((floatToString as kotlin.reflect.KFunction<*>).call(1.5f))

    val doubleToString: (Double) -> String = Double::toString
    val boundDouble: () -> String = (2.5)::toString
    val nullableDoubleToString: (Double?) -> String = Double?::toString
    val nullableNegativeZero: Double? = -0.0
    println(doubleToString(2.5))
    println(doubleToString(-0.0))
    println(boundDouble())
    println(2.5.toString())
    println(nullableDoubleToString(null))
    println(nullableDoubleToString(nullableNegativeZero))
    println((doubleToString as kotlin.reflect.KFunction<*>).call(2.5))

    val boundLong: () -> String = Long.MIN_VALUE::toString
    val nullableLongToString: (Long?) -> String = Long?::toString
    println(longToString(Long.MIN_VALUE))
    println(longToString(Long.MAX_VALUE))
    println(boundLong())
    println(Long.MIN_VALUE.toString())
    println(nullableLongToString(null))
    println(nullableLongToString(1L))
    println((longToString as kotlin.reflect.KFunction<*>).call(Long.MIN_VALUE))

    val ulongToString: (ULong) -> String = ULong::toString
    val boundULong: () -> String = 18446744073709551615uL::toString
    val nullableULongToString: (ULong?) -> String = ULong?::toString
    val nullableHighBit: ULong? = 9223372036854775808uL
    println(ulongToString(0uL))
    println(ulongToString(9223372036854775808uL))
    println(ulongToString(18446744073709551615uL))
    println(boundULong())
    println(18446744073709551615uL.toString())
    println(nullableULongToString(null))
    println(nullableULongToString(nullableHighBit))
    println((ulongToString as kotlin.reflect.KFunction<*>).call(18446744073709551615uL))

    val uintToString: (UInt) -> String = UInt::toString
    val ubyteToString: (UByte) -> String = UByte::toString
    val ushortToString: (UShort) -> String = UShort::toString
    println(uintToString(4294967295u))
    println(ubyteToString(255u.toUByte()))
    println(ushortToString(65535u.toUShort()))
}
