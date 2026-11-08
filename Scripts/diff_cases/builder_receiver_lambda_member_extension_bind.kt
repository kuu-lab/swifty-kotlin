// DIFF_JVM
// KUU-4079: receiver-lambda DSL type inference must solve the outer type
// variable from a member-extension call inside the lambda body
// (kotlin-result's `binding { result.bind() }` shape). `bind`'s declared
// `Outcome<V, E>` receiver mentions `E` only through the dispatch receiver
// `BindingScope<E>`; matching `Outcome<Int, String>` must pin `E = String`.
interface Outcome<out V, out E>
class Ok<V>(val value: V) : Outcome<V, Nothing>
class Err<E>(val error: E) : Outcome<Nothing, E>

interface BindingScope<E> {
    fun <V> Outcome<V, E>.bind(): V
}

class BindingScopeImpl<E> : BindingScope<E> {
    override fun <V> Outcome<V, E>.bind(): V {
        val ok = this as Ok<V>
        return ok.value
    }
}

fun <V, E> binding(block: BindingScope<E>.() -> V): Outcome<V, E> =
    Ok(BindingScopeImpl<E>().block())

fun parse(fail: Boolean): Outcome<Int, String> =
    if (fail) Err("bad") else Ok(41)

fun main() {
    val result = binding {
        val a = parse(false).bind()
        a + 1
    }
    val ok = result as Ok<Int>
    println(ok.value)
}
