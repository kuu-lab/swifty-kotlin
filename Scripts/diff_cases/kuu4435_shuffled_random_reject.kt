// CANDIDATE-ONLY: shuffled(random:) takes kotlin.random.Random; passing any
// other type is a compile error on kotlinc ("Argument type mismatch: actual
// type is 'Int', but 'Random' was expected"). KSwiftK used to bind the call
// through the synthetic collection fallback without checking the argument
// and crashed with a vtable panic at runtime (KUU-4435). Compare the
// diagnostics with kuu4435_shuffled_random_reject.expected.stderr.
fun main() {
    println(listOf(1, 2, 3).shuffled(42))
    println(sequenceOf(1, 2, 3).shuffled(42))
    println(mutableListOf(1, 2, 3).shuffled("x"))
    println(setOf(1, 2, 3).shuffled(1.5))
}
