import kotlinx.coroutines.*

// KUU-4095: bundled coroutineScope / supervisorScope are <R>-generic like
// upstream, so explicit type arguments resolve and the block's result type
// flows through the signature.

fun compute(): String = "hello"

fun main() = runBlocking {
    // Explicit type arguments on both builders.
    val a: Int = coroutineScope<Int> { 5 }
    val b: Int = supervisorScope<Int> { 6 }
    println(a + b)

    // Inferred R keeps member access statically typed on the call result.
    println(coroutineScope { compute() }.length)
    println(supervisorScope { compute() }.uppercase())

    // A declared destination type constrains R just like any generic call.
    val c: String = coroutineScope { compute() }
    val d: Number = supervisorScope { 7 }
    println("$c:$d")

    // Nested scopes keep their own type parameters.
    val nested = coroutineScope {
        supervisorScope { "inner" } + coroutineScope { "!" }
    }
    println(nested)
}
