// KUU-2100: Double equality against Any? must preserve the boxed primitive type.
fun equalsNullableAny(a: Double, b: Any?): Boolean = a == b
fun equalsNonNullAny(a: Double, b: Any): Boolean = a == b

fun main() {
    println(equalsNullableAny(0.0, 0))
    println(equalsNonNullAny(0.0, 0))
    println(equalsNullableAny(0.0, 0.0))
    println(equalsNullableAny(-0.0, 0.0))
    println(equalsNullableAny(Double.NaN, Double.NaN))
    println(equalsNullableAny(0.0, null))
}
