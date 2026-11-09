// DIFF_JVM
// KUU-4179: an unannotated lambda returned through a generic higher-order
// call (let/run) must receive its parameter types from a *nullable* function
// expected type, including when the call sits in argument position behind a
// safe call (`onCancellation?.let { ... }` in kotlinx-coroutines'
// CancellableContinuationImpl.resumeImpl).
fun resumeImpl(cb: ((Int, Int, Int) -> Int)?) = cb

fun main() {
    val base: (Int) -> Int = { it + 1 }
    val nullable: ((Int) -> Int)? = base

    val viaLet: ((Int, Int) -> Int)? = base.let { { a, b -> a + b } }
    val viaRun: ((Int, Int) -> Int)? = base.run { { a, b -> a * b } }
    val viaSafeLet: ((Int, Int) -> Int)? = nullable?.let { { a, b -> a - b } }
    val dispatched = resumeImpl(nullable?.let { { a, b, c -> a + b + c } })

    println(viaLet?.invoke(1, 2))
    println(viaRun?.invoke(3, 4))
    println(viaSafeLet?.invoke(10, 3))
    println(dispatched?.invoke(1, 2, 3))
}
