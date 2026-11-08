sealed interface E<out A, out B>
data class L<out A>(val value: A) : E<A, Nothing>

fun <A, B> E<A, B>.g(p: (A) -> Boolean): Boolean =
    this@g is L<A> && p(value)

fun <A, B> E<A, B>.h(): Int =
    if (this@h is L<*>) this@h.value.hashCode() else -1

fun <A, B> E<A, B>.k(): Int = run {
    if (this@k is L<*>) this@k.value.hashCode() else -1
}

fun main() {
    val e: E<Int, String> = L(41)
    println(e.g { it > 40 })
    println(e.h())
    println(e.k())
}
