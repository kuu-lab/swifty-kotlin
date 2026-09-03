import kotlin.reflect.KProperty0

var sourceValue: Int = 7
val delegatedValue by ::sourceValue
lateinit var lateinitValue: String

fun main() {
    val property: KProperty0<Int> = ::sourceValue
    println(property.getValue(null, property))
    println(delegatedValue)
    println(::lateinitValue.isInitialized)
    lateinitValue = "ready"
    println(::lateinitValue.isInitialized)
}
