// Minimal reproduction for a function-valued parameter used from a suspend
// Flow-style collector lambda.

interface TestFlow

suspend fun TestFlow.collect(collector: suspend (Int) -> Unit) {
}

suspend fun TestFlow.fold(
    initial: Int,
    operation: suspend (Int, Int) -> Int
): Int {
    collect { value -> operation(initial, value) }
    return initial
}

fun main() {}
