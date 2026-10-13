import kotlin.reflect.KProperty
class ValueDelegate
operator fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 1
fun main() {
    operator fun ValueDelegate.getValue(thisRef: Any?, property: KProperty<*>): Int = 2
    val answer by ValueDelegate()
    println(answer)
}
