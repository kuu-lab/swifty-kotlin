import kotlin.reflect.KProperty

// KUU-3947: accessor-backed property references must render the JVM-style
// `val pkg.Owner.name: kotlin.T` signature instead of `<object 0x…>`.

class Named(val value: Int, var mutable: String, val list: List<Int>)
var memberProp: Int = 7
val topVal: List<Int> = listOf(1)
val String.extVal: Int get() = length

class IntDelegate {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): Int {
        println(property)
        return 7
    }
}
val topDelegated by IntDelegate()

class StrDelegate {
    operator fun getValue(thisRef: Any?, property: KProperty<*>): String = "S($property)"
}
val String.extDel by StrDelegate()

fun take(f: (Named) -> Int) { println(f) }

fun main() {
    println(Named::value)
    println(::memberProp)
    println(::topVal)
    println(topDelegated)
    val n = Named(1, "s", listOf(2))
    println(n::list)
    println(String::extVal)
    println("ab"::extVal)
    take(Named::value)
    println("x".extDel)
}
