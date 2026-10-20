package kotlin.sequences
@kotlin.coroutines.RestrictsSuspension
abstract class SequenceScope<in T> internal constructor() {
    abstract suspend fun yield(value: T)
    abstract suspend fun yieldAll(iterator: Iterator<T>)
    suspend fun yieldAll(elements: Iterable<T>) {}
    suspend fun yieldAll(sequence: Sequence<T>) {}
}
fun <T> sequence(block: suspend SequenceScope<T>.() -> Unit): Sequence<T> = null!!
fun <T> iterator(block: suspend SequenceScope<T>.() -> Unit): Iterator<T> = null!!