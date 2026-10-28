// KOTLINC_FLAGS: -Xjdk-release=17
fun nullableDouble(value: Double?): String = value.toString()

fun main() {
    val anyReference: (Any) -> String = Any::toString
    println(anyReference(true))
    println(anyReference(false))
    println(anyReference('A'))
    println(anyReference(1.5f))
    println(anyReference(2.5))
    val boxedBoolean: Any = true
    println(anyReference(boxedBoolean))
    val bound: () -> String = boxedBoolean::toString
    println(bound())

    val doubleReference: (Double?) -> String = Double?::toString
    val boxedDouble: Double? = -0.0
    println(doubleReference(null))
    println(doubleReference(-0.0))
    println(doubleReference(boxedDouble))
    println(nullableDouble(-0.0))
    val lambda: (Double?) -> String = { it.toString() }
    println(lambda(-0.0))
}
