@file:kotlin.jvm.JvmName("SequencesKt")
package kotlin.sequences
import kotlin.coroutines.*
import kotlin.jvm.internal.*
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
@RestrictsSuspension
abstract class SequenceScope<in T> {
    abstract suspend fun yield(value: T)
    abstract suspend fun yieldAll(iterator: Iterator<T>)
    suspend fun yieldAll(elements: Iterable<T>) { yieldAll(elements.iterator()) }
    suspend fun yieldAll(sequence: Sequence<T>) { yieldAll(sequence.iterator()) }
}
private class BuilderIterator<T>(private val block: suspend SequenceScope<T>.() -> Unit): SequenceScope<T>(), Iterator<T>, Continuation<Unit> {
    private var started = false
    // 0: needs resume, 1: delegated iterator needs hasNext, 2: delegated item,
    // 3: single item, 4: complete, 5: failed.
    private var state = 0
    private var item: T? = null
    private var delegated: Iterator<T>? = null
    private var step: Continuation<Unit>? = null
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: kotlin.Result<Unit>) {
        kotlin.throwOnFailure(__jvmResultValue(result))
        state = 4
    }
    override suspend fun yield(value: T) {
        item = value
        state = 3
        suspendCoroutine<Unit> { continuation -> step = continuation }
    }
    override suspend fun yieldAll(iterator: Iterator<T>) {
        if (!iterator.hasNext()) return
        delegated = iterator
        state = 2
        suspendCoroutine<Unit> { continuation -> step = continuation }
    }
    override fun hasNext(): Boolean {
        while (true) {
            if (state == 2 || state == 3) return true
            if (state == 4) return false
            if (state == 5) throw IllegalStateException("Iterator has failed.")
            if (state == 1) {
                if (delegated!!.hasNext()) { state = 2; return true }
                delegated = null
            }
            state = 5
            if (!started) {
                started = true
                val callback = block as (SequenceScope<T>, Continuation<Unit>) -> Any?
                kotlin.coroutines.startEncoded(callback, this, this)
            } else {
                val next = step
                step = null
                if (next != null) __jvmResume(next, Unit)
            }
        }
        return false
    }
    override fun next(): T {
        if (!hasNext()) throw NoSuchElementException()
        if (state == 2) { state = 1; return delegated!!.next() }
        state = 0
        val value = item as T
        item = null
        return value
    }
}
fun <T> sequence(block: suspend SequenceScope<T>.() -> Unit): Sequence<T> = object: Sequence<T> {
    override fun iterator(): Iterator<T> = BuilderIterator(block)
}
fun <T> iterator(block: suspend SequenceScope<T>.() -> Unit): Iterator<T> = BuilderIterator(block)
