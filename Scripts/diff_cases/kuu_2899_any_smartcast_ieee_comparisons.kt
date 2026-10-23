// KUU-2899: Any smartcasts must use IEEE primitive comparison semantics.
fun eq5(a: Any?, b: Any?): Boolean? = if (a is Double && b is Double) a == b else null
fun lt5(a: Any?, b: Any?): Boolean? = if (a is Double && b is Double) a < b else null

fun doubleComparisons(a: Any?, b: Any?) {
    if (a is Double && b is Double) {
        println(a == b)
        println(a != b)
        println(a < b)
        println(a > b)
        println(a <= b)
        println(a >= b)
    } else {
        println("not-double")
    }
}

fun floatComparisons(a: Any?, b: Any?) {
    if (a is Float && b is Float) {
        println(a == b)
        println(a != b)
        println(a < b)
        println(a > b)
        println(a <= b)
        println(a >= b)
    } else {
        println("not-float")
    }
}

fun whenDouble(value: Any?): String = if (value is Double) when (value) {
    -0.0 -> "zero"
    Double.NaN -> "nan"
    else -> "other"
} else "not-double"

fun whenFloat(value: Any?): String = if (value is Float) when (value) {
    -0.0f -> "zero"
    Float.NaN -> "nan"
    else -> "other"
} else "not-float"

fun declaredDoubleEquals(a: Double?, b: Double?): Boolean = a!! == b!!
fun boxedEquals(a: Any?, b: Any?): Boolean = a == b

fun main() {
    println(eq5(-0.0, 0.0))
    println(lt5(-0.0, 0.0))
    doubleComparisons(-0.0, 0.0)
    doubleComparisons(Double.NaN, Double.NaN)
    doubleComparisons(Double.NaN, 0.0)
    doubleComparisons(null, 0.0)
    floatComparisons(-0.0f, 0.0f)
    floatComparisons(Float.NaN, Float.NaN)
    floatComparisons(Float.NaN, 0.0f)
    floatComparisons(null, 0.0f)
    println(whenDouble(-0.0))
    println(whenDouble(0.0))
    println(whenDouble(Double.NaN))
    println(whenDouble(null))
    println(whenFloat(-0.0f))
    println(whenFloat(0.0f))
    println(whenFloat(Float.NaN))
    println(whenFloat(null))
    println(declaredDoubleEquals(-0.0, 0.0))
    println(declaredDoubleEquals(Double.NaN, Double.NaN))
    println(boxedEquals(-0.0, 0.0))
    println(boxedEquals(Double.NaN, Double.NaN))
}
