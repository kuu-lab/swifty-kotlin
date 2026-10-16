// KUU-2203: a Unit upper bound makes the lambda result Unit-coercible.
// Based on JetBrains Kotlin 2.3.10 compiler/testData/diagnostics/tests/inference/UnitUpperboundLambdaReturnType.kt.
// DIAGNOSTICS: -FINAL_UPPER_BOUND
fun <U : Unit> fork(task: () -> U) {}

fun <T> infer(task: () -> T) {}

fun consume(task: () -> Unit) {}

fun test() {
    fork {}
    fork { Unit }
    fork { 42 }
    fork<Unit> { 42 }
    consume { 42 }
    infer { 42 }
}

fun main() {
    test()
    println("OK")
}
