// KUU-4340: an unqualified extension property on the same receiver type
// resolves inside an extension function body. The property's own type
// parameter is instantiated from the receiver (`Cell<V>` supplies `T := V`),
// matching the explicit `this.value` getter result — previously this was
// KSWIFTK-SEMA-0022 unresolved reference, and a naive binding read an
// uninitialized global slot instead of calling the getter.
package probe

class Cell<V>(val initialValue: V) { fun get(): V = initialValue }

val <T> Cell<T>.value: T get() = get()

fun <V> Cell<V>.readIt(): V = value
fun <V> Cell<V>.readThis(): V = this.value
fun Cell<Int>.readConcrete(): Int = value

fun main() {
    val a = Cell(41)
    println(a.readIt())
    println(a.readThis())
    println(a.readIt() + 1)
    println(a.readConcrete())
}
