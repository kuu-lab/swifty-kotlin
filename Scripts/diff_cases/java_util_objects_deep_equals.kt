// KUU-2068: KotlinPoet's annotation-default comparison needs this JVM facade.
// KOTLINC_FLAGS: -Xjdk-release=17
import java.util.Objects
import java.util.Objects as JavaObjects

fun same(left: Any?, right: Any?): Boolean = Objects.deepEquals(left, right)
fun same(left: Array<Any?>, right: Array<Any?>): Boolean = left.contentDeepEquals(right)

class Value(val number: Int) {
    override fun equals(other: Any?): Boolean = other is Value && number == other.number
    override fun hashCode(): Int = number
}

class ThrowingEquality {
    override fun equals(other: Any?): Boolean = throw IllegalStateException("equals")
    override fun hashCode(): Int = 0
}

fun main() {
    println(same(null, null))
    println(same(null, "x"))
    println(same("x", null))
    println(same("equal", "equal"))
    println(same(1, 1))
    println(same(1, 1L))
    println(same(Value(7), Value(7)))
    println(same(Value(7), Value(8)))
    println(JavaObjects.deepEquals(null, null))
    println(java.util.Objects.deepEquals(null, null))

    val left = arrayOf<Any?>(Value(7), arrayOf<Any?>(intArrayOf(1, 2), null), "end")
    val equal = arrayOf<Any?>(Value(7), arrayOf<Any?>(intArrayOf(1, 2), null), "end")
    val different = arrayOf<Any?>(Value(7), arrayOf<Any?>(intArrayOf(1, 3), null), "end")
    println(Objects.deepEquals(left, equal))
    println(Objects.deepEquals(left, different))
    println(Objects.deepEquals(left, left))
    println(left.contentDeepEquals(equal))
    println(left.contentDeepEquals(different))
    println(same(left, equal))
    println(same(emptyArray<Any?>(), emptyArray<String>()))
    println(same(arrayOf("x"), arrayOf<Any?>("x")))
    println(same(arrayOf("x"), arrayOf("x", "y")))
    println(same(intArrayOf(1), longArrayOf(1L)))
    println(same(intArrayOf(1), arrayOf(1)))
    println(same(arrayOf(1), intArrayOf(1)))
    println(same(intArrayOf(1), null))
    println(same(null, intArrayOf(1)))

    val primitives: Array<Any> = arrayOf(
        byteArrayOf(1, -2), shortArrayOf(1, -2), intArrayOf(1, -2), longArrayOf(1L, -2L),
        charArrayOf('a', 'b'), booleanArrayOf(true, false),
        floatArrayOf(Float.NaN, -0.0f), doubleArrayOf(Double.NaN, -0.0)
    )
    val copies: Array<Any> = arrayOf(
        byteArrayOf(1, -2), shortArrayOf(1, -2), intArrayOf(1, -2), longArrayOf(1L, -2L),
        charArrayOf('a', 'b'), booleanArrayOf(true, false),
        floatArrayOf(Float.NaN, -0.0f), doubleArrayOf(Double.NaN, -0.0)
    )
    val changed: Array<Any> = arrayOf(
        byteArrayOf(1, 2), shortArrayOf(1, 2), intArrayOf(1, 2), longArrayOf(1L, 2L),
        charArrayOf('a', 'c'), booleanArrayOf(true, true),
        floatArrayOf(Float.NaN, 0.0f), doubleArrayOf(Double.NaN, 0.0)
    )
    for (index in primitives.indices) {
        println(same(primitives[index], copies[index]))
        println(same(primitives[index], changed[index]))
    }
    println(same(arrayOf<Any>(intArrayOf(1)), arrayOf<Any>(longArrayOf(1L))))
    println(same(floatArrayOf(Float.fromBits(0x7fc00001)), floatArrayOf(Float.fromBits(0x7fc00002))))
    println(same(doubleArrayOf(Double.fromBits(0x7ff8000000000001L)), doubleArrayOf(Double.fromBits(0x7ff8000000000002L))))
    println(same(Float.fromBits(0x7fc00001), Float.fromBits(0x7fc00002)))
    println(same(Double.fromBits(0x7ff8000000000001L), Double.fromBits(0x7ff8000000000002L)))
    println(same(-0.0f, 0.0f))
    println(same(-0.0, 0.0))
    println(same(Float.NaN, Double.NaN))
    val throwing = ThrowingEquality()
    println(same(throwing, throwing))
    println(same(throwing, null))
    println(Objects.deepEquals(arrayOf<Any?>(null), arrayOf<Any?>(throwing)))
    try {
        same(throwing, ThrowingEquality())
        println("not thrown")
    } catch (failure: IllegalStateException) {
        println(failure.message)
    }
    try {
        Objects.deepEquals(arrayOf<Any?>(throwing), arrayOf<Any?>(null))
        println("not thrown")
    } catch (failure: IllegalStateException) {
        println("nested: " + failure.message)
    }
}
