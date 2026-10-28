// KUU-3675: a generic extension invoked on a builtin/synthetic companion
// receiver (`(String).f { ... }`) left the companion's global root slot
// zero, so the erased function-value adapter's nominal cast threw and the
// program exited with an unhandled top-level exception. Synthetic
// companions never had an initializer synthesized for them because they
// have no AST object declaration. Kotlin/JVM prints true/false/true/true.
fun <T> T.f(E: (y: T) -> String): Boolean = E(this).isEmpty()
fun <T> T.g(x: Int): Boolean = x > 0

fun fu1() = (String).f { v -> "" }
fun fu2() = (Int).f { v -> "x" }
fun fu3() = (String).g(7)
fun fu4() = "lit".f { v -> "" }

fun main() {
    println(fu1())
    println(fu2())
    println(fu3())
    println(fu4())
}
