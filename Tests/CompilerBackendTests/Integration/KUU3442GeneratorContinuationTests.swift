@testable import CompilerCore
import Testing

@Suite(.serialized)
struct KUU3442GeneratorContinuationTests {
    @Test
    func virtualYieldKeepsItsUninterceptedContinuation() throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*
            import kotlin.coroutines.intrinsics.*

            fun box(): String {
                val first = gen().joinToString()
                val second = gen().joinToString()
                return "$first|$second"
            }

            private var was = false

            private fun gen() = generate<Int> {
                if (was) {
                    yield(-1)
                    return@generate
                }
                for (i in 1..2) yield(i)
                was = true
            }

            private interface Generator<in T> {
                suspend fun yield(value: T)
            }

            private fun <T> generate(block: suspend Generator<T>.() -> Unit): Sequence<T> =
                GeneratedSequence(block)

            private class GeneratedSequence<out T>(
                private val block: suspend Generator<T>.() -> Unit
            ) : Sequence<T> {
                override fun iterator(): Iterator<T> = GeneratedIterator(block)
            }

            private class GeneratedIterator<T>(
                block: suspend Generator<T>.() -> Unit
            ) : AbstractIterator<T>(), Generator<T> {
                private var nextStep: Continuation<Unit> = block.createCoroutine(
                    this,
                    object : Continuation<Unit> {
                        override val context = EmptyCoroutineContext
                        override fun resumeWith(data: Result<Unit>) {
                            data.getOrThrow()
                            done()
                        }
                    }
                )

                override fun computeNext() {
                    nextStep.resume(Unit)
                }

                override suspend fun yield(value: T) =
                    suspendCoroutineUninterceptedOrReturn<Unit> { continuation ->
                        setNext(value)
                        nextStep = continuation
                        COROUTINE_SUSPENDED
                    }
            }

            fun main() {
                println(box())
            }
            """,
            expectedOutput: "1, 2|-1\n",
            moduleName: "KUU3442GeneratorContinuation"
        )
    }

    @Test
    func asyncIteratorYieldKeepsItsStoredContinuation() throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*
            import kotlin.coroutines.intrinsics.*

            interface AsyncGenerator<in T> {
                suspend fun yield(value: T)
            }

            interface AsyncSequence<out T> {
                operator fun iterator(): AsyncIterator<T>
            }

            interface AsyncIterator<out T> {
                suspend operator fun hasNext(): Boolean
                suspend operator fun next(): T
            }

            fun <T> asyncGenerate(block: suspend AsyncGenerator<T>.() -> Unit): AsyncSequence<T> =
                object : AsyncSequence<T> {
                    override fun iterator(): AsyncIterator<T> {
                        val iterator = AsyncGeneratorIterator<T>()
                        iterator.nextStep = block.createCoroutine(receiver = iterator, completion = iterator)
                        return iterator
                    }
                }

            class AsyncGeneratorIterator<T> : AsyncIterator<T>, AsyncGenerator<T>, Continuation<Unit> {
                var computedNext = false
                var nextValue: T? = null
                var nextStep: Continuation<Unit>? = null
                var computesNext = false
                var computeContinuation: Continuation<*>? = null

                override val context = EmptyCoroutineContext

                suspend fun computeHasNext(): Boolean =
                    suspendCoroutineUninterceptedOrReturn { continuation ->
                        computesNext = false
                        computeContinuation = continuation
                        nextStep!!.resume(Unit)
                        COROUTINE_SUSPENDED
                    }

                suspend fun computeNext(): T =
                    suspendCoroutineUninterceptedOrReturn { continuation ->
                        computesNext = true
                        computeContinuation = continuation
                        nextStep!!.resume(Unit)
                        COROUTINE_SUSPENDED
                    }

                @Suppress("UNCHECKED_CAST")
                fun resumeIterator(exception: Throwable?) {
                    if (exception != null) {
                        done()
                        computeContinuation!!.resumeWithException(exception)
                        return
                    }
                    if (computesNext) {
                        computedNext = false
                        (computeContinuation as Continuation<T>).resume(nextValue as T)
                    } else {
                        (computeContinuation as Continuation<Boolean>).resume(nextStep != null)
                    }
                }

                override suspend fun hasNext(): Boolean {
                    if (!computedNext) return computeHasNext()
                    return nextStep != null
                }

                override suspend fun next(): T {
                    if (!computedNext) return computeNext()
                    computedNext = false
                    return nextValue as T
                }

                private fun done() {
                    computedNext = true
                    nextStep = null
                }

                override fun resumeWith(result: Result<Unit>) {
                    done()
                    resumeIterator(result.exceptionOrNull())
                }

                override suspend fun yield(value: T): Unit =
                    suspendCoroutineUninterceptedOrReturn { continuation ->
                        computedNext = true
                        nextValue = value
                        nextStep = continuation
                        resumeIterator(null)
                        COROUTINE_SUSPENDED
                    }
            }

            private class EmptyContinuation : Continuation<Unit> {
                override val context = EmptyCoroutineContext
                override fun resumeWith(result: Result<Unit>) {
                    result.getOrThrow()
                }
            }

            fun builder(block: suspend () -> Unit) {
                block.startCoroutine(EmptyContinuation())
            }

            fun box(): String {
                val sequence = asyncGenerate<String> {
                    yield("O")
                    yield("K")
                }
                var result = ""
                builder {
                    for (item in sequence) result += item
                }
                return result
            }

            fun main() {
                println(box())
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3442AsyncIteratorContinuation"
        )
    }
}
