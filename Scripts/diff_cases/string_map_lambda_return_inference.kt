// KUU-4125: on a `String` receiver the `map`/`mapIndexed`/`mapNotNull`
// String-HOF special path pre-infers the lambda against the placeholder
// expected type `(Char) -> Any?`, then feeds that bound type to overload
// resolution. `R` used to get a lower bound of `Any?` that conflicted with
// the upper bound coming from an expected `List<R>` (KSWIFTK-TYPE-0001
// Conflicting bounds). The lambda body's inferred return type must drive
// `R` instead.
fun <R> onString(transform: (Char) -> R, s: String): List<R> = s.map { transform(it) }
fun echo(s: String): List<Char> = s.map { it }
inline fun <R> onStringInlined(crossinline transform: (Char) -> R, s: String): List<R> =
    s.map { transform(it) }

fun main() {
    println(onString({ it.code }, "ab"))
    println(echo("xy"))
    println(onStringInlined({ it.code }, "pq"))
    println("ab".map { it })
    val s: String = "ab"
    println(s.mapNotNull { if (it == 'a') null else it.code })
    println(s.mapIndexed { i, c -> i + c.code })
    println(s.map { it.code + 1 })
}
