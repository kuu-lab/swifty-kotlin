class G<T, R>(val t: T, val r: R? = null)
class W<T>(val g: G<T, T>)

fun <T, R> create(t: T, r: R? = null): G<T, R> = G(t, r)
fun <T> wrap(g: G<T, T>): W<T> = W(g)
fun <T : Any> make(t: T): W<T> = W(G(t))
fun <T : Any> makeNamed(t: T): W<T> = W(g = G(t = t))
fun <T : Any> makeFunction(t: T): W<T> = wrap(create(t))
fun <T : Any> direct(t: T): G<T, T> = G(t)

fun main() {
    println(make("ctor").g.t)
    println(makeNamed(42).g.t)
    println(makeFunction("function").g.t)
    println(direct(7).t)
    println(make("default").g.r)
}
