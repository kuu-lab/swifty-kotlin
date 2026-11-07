// EXPECT-REJECT
// KUU-4408: kotlinc rejects an unannotated generic callable reference whose
// type parameters neither an expected type nor the receiver can supply,
// instead of binding it with unresolved type variables.
fun <T> gen(value: T): T = value
fun <T> unused(value: Int): Int = value
class Foo<T>(val x: T)
fun main() {
    val a = ::gen
    val b = ::unused
    val c = ::Foo
}
