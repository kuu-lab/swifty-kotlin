// Regression (KUU-3781): a contextual property whose getter returns a
// context-bound anonymous function must capture the call-site context
// argument, not leak the outer `with` receiver. Mirrors the JetBrains
// contextParameters/sameNameWithOuterContext.kt case that SIGSEGV'd on the
// ticket's baseline.

context(a: String)
val p
    get() = context(a: String) fun (): String { return a }

fun main() {
    with("!") {
        println(p("OK"))
    }
}
