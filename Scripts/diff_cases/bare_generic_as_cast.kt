// KUU-1324: a bare cast recovers type arguments from the known superclass.
open class Desc<T : Any, R>(val t: T, val defaultValue: R?)
class ArgD<T : Any, R>(t: T, dv: R?) : Desc<T, R>(t, dv)

internal inline fun <reified T : Any> Any?.cast(): T = this as T

fun <T : Any> f(d: Desc<T, List<T>>): Int =
    with((d.cast<Desc<T, List<T>>>()) as ArgD) {
        println(defaultValue?.toList())
        1
    }

fun main() {
    println(f(ArgD(7, listOf(7, 8))))
    val d: Desc<Int, List<Int>>? = ArgD(9, listOf(9))
    println((d as? ArgD)?.defaultValue?.toList())
}
