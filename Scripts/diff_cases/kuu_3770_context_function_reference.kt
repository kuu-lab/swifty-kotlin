// DIFF_CANDIDATE_ONLY: Kotlin 2.4.20 rejects references to context-parameter
// functions as contextual function values ("no context argument for 'c' found");
// KSwiftK accepts the adaptation per KUU-3355 semantics.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: kuu_3770_context_function_reference.expected.stdout
// KUU-3770: a callable reference to a context-parameter function keeps its
// `context(X) (...) -> R` type and satisfies a `context(X) (...) -> T`
// expected type — through a generic `T` return, a concrete return, and with
// value parameters following the context slots.
context(c: String) fun ctxLen(): Int = c.length

class Foo { val x = "OK" }

context(f: Foo) fun readX(): String = f.x

context(c: String) fun greet(name: String): String = "$c:$name"

fun <T> withCtx(v: String, f: context(String) () -> T): T = with(v) { f() }
fun <T> withFoo(f: Foo, b: context(Foo) () -> T): T = with(f) { b() }
fun directCtx(v: String, f: context(String) () -> Int): Int = with(v) { f() }
fun applyCtx(v: String, f: context(String) (String) -> String): String = with(v) { f("N") }

fun main() {
    println(withCtx("hi", ::ctxLen))
    println(withFoo(Foo(), ::readX))
    println(directCtx("hey", ::ctxLen))
    println(applyCtx("hi", ::greet))
}
