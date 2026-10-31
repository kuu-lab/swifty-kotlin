// KUU-3805: a vararg callable reference adapted to `(T) -> Int` keeps its
// spread semantics when the generic call's expected result fixes T to an
// array type (JetBrains KT-90169,
// codegen/box/callableReference/adaptedReferences/genericVarargArrayAgainstTypeVariableBoundaries.kt).
fun <T> applyIt(t: T, f: (T) -> Int): Int = f(t)
fun <T> make(f: (T) -> Int): (T) -> Int = f

fun <E> countG(vararg xs: E): Int = xs.size
fun count(vararg xs: Any?): Int = xs.size
fun countS(vararg xs: String): Int = xs.size
fun countCS(vararg xs: CharSequence): Int = xs.size
fun countI(vararg xs: Int): Int = xs.size

class G<E> { fun c(vararg xs: E): Int = xs.size }

fun check(name: String, actual: Int, expected: Int = 2): String =
    if (actual != expected) "FAIL $name: $actual" else "OK $name"

fun main() {
    val arr = arrayOf("a", "b")
    val f: (Array<String>) -> Int = ::countG
    val g: (Array<String>) -> Int = make(::countG)
    println(check("count", applyIt(arr, ::count)))
    println(check("countS", applyIt(arr, ::countS)))
    println(check("countCS", applyIt(arr, ::countCS)))
    println(check("let countS", arr.let(::countS)))
    println(check("expected function type", f(arr)))
    println(check("make", g(arr)))
    println(check("G<String>", applyIt(arr, G<String>()::c)))
    println(check("G<Any?>", applyIt(arr, G<Any?>()::c)))
    println(check("spread lambda", applyIt(arr) { countG(*it) }))
    println(check("lambda", applyIt(arr) { countG(it) }, expected = 1))
    println(check("countI", applyIt(intArrayOf(1, 2), ::countI)))
    println(check("String", applyIt("x", ::countG), expected = 1))
    println(check("IntArray", applyIt(intArrayOf(1, 2), ::countG), expected = 1))
}
