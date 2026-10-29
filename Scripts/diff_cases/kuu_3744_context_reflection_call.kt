// DIFF_CANDIDATE_ONLY: Kotlin 2.4.20 rejects the context-function reference adaptation.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kuu_3744_context_reflection_call.expected.stdout
import kotlin.reflect.KFunction
import kotlin.reflect.KParameter

context(c: String) fun sizeWithExtra(n: Int): Int = c.length + n
fun inspect(f: context(String) (Int) -> Int) {
    val callable = f as KFunction<Int>
    println(callable.parameters.size)
    println(callable.parameters[0].kind == KParameter.Kind.CONTEXT)
    println(callable.parameters[0].name)
    println(callable.parameters[1].name)
    println(callable.call("test", 3))
}
fun main() { inspect(::sizeWithExtra) }
