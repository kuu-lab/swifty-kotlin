// DIFF_CANDIDATE_ONLY: Kotlin 2.4.20 rejects this generic context-function reference adaptation.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kuu_3355_context_callable_reference.expected.stdout
// KUU-3355: a context function callable reference passed through a generic wrapper.
context(c: String) fun ctxLen(): Int = c.length
fun <T> withCtx(v: String, f: context(String) () -> T): T = with(v) { f() }
fun main() { println(withCtx("hi", ::ctxLen)) }
