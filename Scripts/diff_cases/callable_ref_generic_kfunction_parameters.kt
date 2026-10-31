// KUU-3886: a callable reference to a generic declaration conformed to
// KFunctionN needs an ABI-only adapter (erased parameter inputs), but the
// value still exposes KCallable reflection metadata. Previously the adapter
// hid KCallable identity, so `.parameters` fell back to an itable dispatch
// and crashed with KSWIFTK-RUNTIME-0001.
class Box<T>(val t: T)
fun <Q> gen(q: Q): Q = q

fun main() {
    val ref: kotlin.reflect.KFunction1<Int, Box<Int>> = ::Box
    println(ref.parameters.size)
    println(ref(7).t)
    println(ref.call(8).t)
    val ref2: kotlin.reflect.KFunction1<Int, Int> = ::gen
    println(ref2.parameters.size)
    println(ref2.name)
    println(ref2(42))
}
