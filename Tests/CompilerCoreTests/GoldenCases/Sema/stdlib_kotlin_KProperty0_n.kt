import kotlin.reflect.KProperty0

// KUU-1597 Sema owner: pin property-reference, delegated getValue, and lateinit isInitialized resolution; observed values stay in Scripts/diff_cases/stdlib_kotlin_KProperty0_n.kt.
var sourceValue: Int = 7
val delegatedValue by ::sourceValue
lateinit var lateinitValue: String

fun main() {
    val property: KProperty0<Int> = ::sourceValue
    val propertyValue: Int = property.getValue(null, property)
    val delegated: Int = delegatedValue
    val initiallyInitialized: Boolean = ::lateinitValue.isInitialized
    lateinitValue = "ready"
    val initialized: Boolean = ::lateinitValue.isInitialized
}
