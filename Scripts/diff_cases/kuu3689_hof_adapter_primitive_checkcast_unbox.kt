// Regression for KUU-3689. A function-value adapter param whose type is a
// concrete non-null primitive still goes through the erased-boundary
// checkcast; argument normalization boxes that operand, so the adapter must
// unbox the cast result again before forwarding it to the lambda's raw
// arithmetic. Previously the tagged IntBox handle was added as a raw word and
// the result box failed the Long cast, panicking at the top level.
fun <A> fold(seed: A, step: (Int, A) -> A): A = step(1, seed)
fun <A> foldLongFirst(seed: A, step: (Long, A) -> A): A = step(1L, seed)
fun <A> foldMiddle(seed: A, step: (A, Int, A) -> A): A = step(seed, 2, seed)

fun main() {
    println(fold(0) { element: Int, accumulator: Long -> accumulator + element })
    println(fold(0L) { element: Int, accumulator: Long -> accumulator + element })
    println(fold<Long>(0) { element: Int, accumulator: Long -> accumulator + element })
    println(fold(0) { element: Int, accumulator: Int -> accumulator + element })
    println(foldLongFirst(0L) { element: Long, accumulator: Long -> accumulator + element })
    println(foldMiddle(0L) { a: Long, e: Int, b: Long -> a + e + b })
}
