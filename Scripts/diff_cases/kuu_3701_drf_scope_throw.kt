// KUU-3701: the DeepRecursive trampoline's scope/function are opaque runtime
// boxes. They must still answer nominal `is`/`as` checks as
// kotlin.DeepRecursiveScope / kotlin.DeepRecursiveFunction — including the
// receiver cast a suspend function value adapter emits for
// `suspend DeepRecursiveScope<Saved, Int>.() -> Int`. And a synchronous throw
// inside an invoked suspend function value (or a nested local suspend fun)
// must propagate to invoke's caller instead of being mistaken for a
// callRecursive park and restarting the block forever.

data class Saved(val k: Int, val f: suspend DeepRecursiveScope<Saved, Int>.() -> Int)

val viaSavedLambda = DeepRecursiveFunction<Saved, Int> { s ->
    with(s) {
        if (k <= 0) f() + 100 else callRecursive(Saved(k - 1, f))
    }
}

val viaLocalThrow = DeepRecursiveFunction<Int, Int> { n ->
    suspend fun DeepRecursiveScope<Int, Int>.b(): Int {
        if (n <= 0) throw RuntimeException("local-boom")
        return callRecursive(n - 1)
    }
    b()
}

fun main() {
    // Non-throwing control: saved suspend lambdas recurse through callRecursive.
    println(viaSavedLambda(Saved(1, { 7 })))
    println(viaSavedLambda(Saved(3, { 9 })))

    // Runtime boxes answer the Kotlin nominal checks they stand in for.
    val probe = DeepRecursiveFunction<Int, Int> { n ->
        println(this is DeepRecursiveScope<*, *>)
        n + 1
    }
    println(probe(41))
    println(probe is DeepRecursiveFunction<*, *>)

    // Synchronous throw inside the invoked suspend function value reaches
    // invoke's caller instead of hanging the trampoline.
    try {
        viaSavedLambda(Saved(0, { throw RuntimeException("boom") }))
        println("unreachable")
    } catch (e: RuntimeException) {
        println("caught:${e.message}")
    }

    // Same throw surfacing through recursive trampoline steps.
    try {
        viaSavedLambda(Saved(2, { throw IllegalStateException("deep") }))
        println("unreachable2")
    } catch (e: IllegalStateException) {
        println("caught2:${e.message}")
    }

    // Throw from a nested local suspend fun after a recursive step.
    try {
        viaLocalThrow(1)
        println("unreachable3")
    } catch (e: RuntimeException) {
        println("caught3:${e.message}")
    }
    println("done")
}
