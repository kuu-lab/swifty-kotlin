// KUU-2750: callRecursive invoked from a nested suspend frame (a local suspend
// fun or a stored suspend function value) parked an inner continuation the
// trampoline could not resume, collapsing the whole invoke to 0.

// callRecursive inside a local suspend fun parks b's child continuation.
val viaLocalFun = DeepRecursiveFunction<Int, Int> { n ->
    suspend fun DeepRecursiveScope<Int, Int>.b(): Int = callRecursive(n - 1)
    if (n <= 0) 0 else b() + 10
}

// A suspend function value stored in a data class, invoked on the scope.
data class Saved(val k: Int, val f: suspend DeepRecursiveScope<Saved, Int>.() -> Int)
val viaSavedLambda = DeepRecursiveFunction<Saved, Int> { s ->
    with(s) {
        suspend fun DeepRecursiveScope<Saved, Int>.b(): Int = callRecursive(Saved(k - 1, f))
        if (k <= 0) f() + 100 else b()
    }
}

// Knuth man-or-boy: saved suspend lambdas that recurse through callRecursive.
typealias Func = suspend DeepRecursiveScope<State, Int>.() -> Int
data class State(
    val k: Int,
    val x1: Func, val x2: Func, val x3: Func,
    val x4: Func, val x5: Func,
)
val manOrBoy = DeepRecursiveFunction<State, Int> { s ->
    with(s) {
        var k = k
        suspend fun DeepRecursiveScope<State, Int>.b(): Int {
            k -= 1
            return callRecursive(State(k, { b() }, x1, x2, x3, x4))
        }
        if (k <= 0) x4() + x5() else b()
    }
}

fun main() {
    println(viaLocalFun(0))
    println(viaLocalFun(1))
    println(viaLocalFun(3))
    println(viaSavedLambda(Saved(1, { 7 })))
    println(viaSavedLambda(Saved(2, { 7 })))
    repeat(12) { k ->
        println(manOrBoy(State(k, { 1 }, { -1 }, { -1 }, { 1 }, { 0 })))
    }
}
