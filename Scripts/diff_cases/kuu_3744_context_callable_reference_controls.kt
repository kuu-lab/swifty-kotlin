// DIFF_CANDIDATE_ONLY: Kotlin 2.4.20 rejects the context-function reference adaptation.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kuu_3744_context_callable_reference_controls.expected.stdout
context(c: String) fun ctxLen(): Int = c.length
fun <T> withCtx(v: String, f: context(String) () -> T): T = with(v) { f() }
fun doubled(value: Int): Int = value * 2

fun main() {
    println(withCtx("abcd", ::ctxLen))
    println(with("xyz") { ctxLen() })
    val ordinary = ::doubled
    println(ordinary(7))
    println(ordinary.call(5))
}
