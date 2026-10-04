// Regression: `catch (e: Exception)` used to be lowered as a catch-all, so it
// swallowed Errors (NotImplementedError, AssertionError, user Error subclasses)
// that must propagate to an outer `catch (t: Throwable)`.
class MyError(message: String) : Error(message)

fun probe(label: String, block: () -> Unit) {
    try {
        try {
            block()
        } catch (e: Exception) {
            println("$label: caught as Exception (${e.message})")
        }
    } catch (t: Throwable) {
        println("$label: reached Throwable (${t.message})")
    }
}

fun main() {
    probe("todo") { TODO("x") }
    probe("assertion") { throw AssertionError("a") }
    probe("user error") { throw MyError("u") }
    probe("state") { error("s") }
    probe("arith") { val zero = 0; println(1 / zero) }
    probe("index") { println(listOf(1)[3]) }

    // Multi-clause: an Error skips the Exception clause and hits Error.
    try {
        TODO("multi")
    } catch (e: Exception) {
        println("wrong: Exception")
    } catch (e: Error) {
        println("right: Error ${e.message}")
    }

    // Single catch (e: Exception) with no outer handler for a non-Error still works.
    val v = try { "x".toInt() } catch (e: Exception) { -1 }
    println(v)
}
