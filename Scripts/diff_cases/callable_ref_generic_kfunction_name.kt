import kotlin.reflect.KFunction1
import kotlin.reflect.KFunction2

class GBox<T>(val v: T)

fun <T> gid(v: T): T = v
fun <T, U> gpair(a: T, b: U): Pair<T, U> = Pair(a, b)
fun id2(v: Int): Int = v + 1

fun main() {
    // KUU-3863: a generic callable reference stored as KFunctionN must keep
    // its KCallable metadata so .name resolves instead of crashing on
    // vtable/itable dispatch.
    val g: KFunction1<Int, Int> = ::gid
    println(g.name)
    println(g(5))
    val g2: KFunction1<Int, Int> = ::gid
    println(g == g2)
    val p: KFunction2<String, Int, Pair<String, Int>> = ::gpair
    println(p.name)
    println(p("a", 1).second)
    val h: KFunction1<Int, Int> = ::id2
    println(h.name)
    println(h(5))
    // Generic constructor reference: invocation must not crash either.
    val ctor: KFunction1<Int, GBox<Int>> = ::GBox
    println(ctor(7).v)
}
