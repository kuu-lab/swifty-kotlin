// Call-site explicit type arguments may end in a trailing comma
// (Kotlin 1.4+). KUU-4140 — the declaration-side fix was KUU-3968;
// call sites parse through a different code path.

fun <T> id(x: T): T = x
fun <T, U> pair(a: T, b: U): T = a
class Box<T>(val v: T) { fun <U> get(u: U): U = u }
fun <T> run0(f: () -> T): T = f()

fun main() {
    println(id<Int,>(1))
    println(pair<Int, String,>(2, "a"))
    println(Box<Int,>(3).v)
    println(Box(0).get<Int,>(4))
    println(id<Int,
    >(5))
    println(id<List<Int,>>(listOf(6)))
    println(run0<Int,> { 7 })
}
