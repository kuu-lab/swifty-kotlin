// KSP-496 follow-up: a bare `::topLevelProperty` reference used to always
// read back the property's value type's default instead of the actual
// value (the underlying global was never actually written to, since a
// const-foldable `val`'s reads are normally inlined as a literal rather
// than routed through the global slot this wrapper's accessor reads).
import kotlin.reflect.KProperty0
import kotlin.reflect.KMutableProperty0

val topLevelConst: Int = 7
var topLevelVar: Int = 10

fun main() {
    val a: KProperty0<Int> = ::topLevelConst
    println("const get: ${a.get()}")

    val b: KMutableProperty0<Int> = ::topLevelVar
    println("var get before: ${b.get()}")
    b.set(99)
    println("var get after: ${b.get()}")
    println("topLevelVar directly: $topLevelVar")
}
