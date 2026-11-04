// Function type-parameter lists may span lines and end in a trailing comma
// (Kotlin 1.4+; Kodein-DI and Store generate this style). KUU-3968.

fun <T,
    P,
> pick(x: P): P = x

inline fun <
    T,
    reified P1,
> tag(p: P1): Int = p.hashCode()

@Target(AnnotationTarget.TYPE_PARAMETER)
annotation class A
fun <T,
    @A P> annotated(x: P): T = TODO()

fun <K : Any, V : Any,> pair(k: K, v: V): String = "$k=$v"

fun main() {
    println(pick<Int, String>("hi"))
    println(tag<Int, Int>(7))
    println(pair<String, Int>("answer", 42))
}
