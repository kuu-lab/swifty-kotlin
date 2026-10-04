import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KProperty0

val topLevelInt: Int = 7
val topLevelString: String = "hi"
var topLevelCounter: Int = 10
fun compute(): Int = 3 + 4
val topLevelComputed: Int = compute()

fun main() {
    val intRef: KProperty0<Int> = ::topLevelInt
    println(intRef.name)
    println(intRef.get())

    val stringRef: KProperty0<String> = ::topLevelString
    println(stringRef.get())

    val counterRef: KMutableProperty0<Int> = ::topLevelCounter
    println(counterRef.get())
    counterRef.set(42)
    println(counterRef.get())
    println(topLevelCounter)

    val computedRef: KProperty0<Int> = ::topLevelComputed
    println(computedRef.get())
}
