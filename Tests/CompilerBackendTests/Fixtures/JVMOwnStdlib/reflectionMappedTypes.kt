class Outer { data class Nested(val value: Int) }
fun listResult(): List<Int> = listOf(1, 2)
fun mapResult(): Map<String, Int> = mapOf("x" to 3)
fun arrayResult(): Array<String> = arrayOf("a", "b")
fun primitiveResult(): IntArray = intArrayOf(4, 5)
fun nestedResult(): Outer.Nested = Outer.Nested(7)
val listProperty: List<Int> = listOf(6)
fun unitResult() {}
fun nullableUnitResult(): Unit? = null
fun main() {
    println(::unitResult.call()); println(::nullableUnitResult.call())
    println(::listResult.call()); println(::listResult.returnType.classifier)
    println(::mapResult.call()); println(::mapResult.returnType.classifier)
    println(::arrayResult.call().joinToString()); println(::arrayResult.returnType.classifier)
    println(::primitiveResult.call().joinToString()); println(::primitiveResult.returnType.classifier)
    println(::nestedResult.call()); println(::nestedResult.returnType.classifier)
    println(::listProperty.get()); println(::listProperty.returnType.classifier)
}
