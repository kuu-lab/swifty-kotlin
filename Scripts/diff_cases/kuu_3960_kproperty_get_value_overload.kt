// DIFF_JVM
// KUU-3960: a `KProperty0<T>.get()` result, typed as the enclosing rigid `T`,
// must flow to the same-shape generic value overload instead of recursively
// re-selecting the `KProperty0` overload — the pattern assertk relies on
// (`assertThat(getter: KProperty0<T>) = assertThat(getter.get(), ...)`).
import kotlin.reflect.KProperty0

var backing: Int = 7
val prop: KProperty0<Int> = ::backing

fun <T> at(v: T): String = "value"
fun <T> at(p: KProperty0<T>): String {
    // The nested call carries the rigid caller `T`: it selects `at(v: T)`,
    // never this same `KProperty0` overload via `V := KProperty0<V>`.
    val nested: String = at(p.get())
    return "prop:$nested"
}

fun main() {
    println(at(prop))
    println(at(42))
}
