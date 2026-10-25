@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.coroutines.CancellationException

public open class CompletableFuture<T> : Future<T>, CompletionStage<T> {
    private var result: T? = null
    private var exception: Throwable? = null
    private var isCompleted: Boolean = false
    private var isCancelledFlag: Boolean = false
    private val completionHandlers = mutableListOf<(T?, Throwable?) -> Unit>()

    public constructor()

    public open fun complete(value: T): Boolean {
        if (isCompleted) return false
        result = value
        isCompleted = true
        notifyCompletionHandlers()
        return true
    }

    public open fun completeExceptionally(ex: Throwable): Boolean {
        if (isCompleted) return false
        exception = ex
        isCompleted = true
        notifyCompletionHandlers()
        return true
    }

    public override fun cancel(mayInterruptIfRunning: Boolean): Boolean {
        if (isCompleted) return false
        exception = CancellationException("CompletableFuture was cancelled")
        isCancelledFlag = true
        isCompleted = true
        notifyCompletionHandlers()
        return true
    }

    public override val isCancelled: Boolean get() = isCancelledFlag
    public override val isDone: Boolean get() = isCompleted

    @Suppress("UNCHECKED_CAST")
    public override fun get(): T {
        if (!isCompleted) {
            throw IllegalStateException("CompletableFuture is not complete; use await() from a coroutine")
        }
        val ex = exception
        if (ex != null) {
            throw ex
        }
        return result as T
    }

    // KUU-3059: the JVM get(timeout, unit) contract — block until the future
    // completes or the deadline passes, then TimeoutException. Waiting uses
    // the per-thread atomicfu parker woken from the completion handlers.
    public override fun get(timeout: Long, unit: TimeUnit): T {
        if (isCompleted) return get()
        val handle = ParkingSupport.currentThreadHandle()
        val deadline = jucDeadlineNanos(unit.toNanos(timeout))
        addCompletionHandler { _, _ -> ParkingSupport.unpark(handle) }
        while (true) {
            if (isCompleted) return get()
            val left = jucNanosLeft(deadline)
            if (left <= 0L) throw TimeoutException()
            jucPark(if (deadline < 0L) -1L else left)
        }
    }

    public open fun join(): T = get()

    public override fun toCompletableFuture(): CompletableFuture<T> = this

    public override fun <U> thenApply(action: (T) -> U): CompletableFuture<U> {
        val dependent = CompletableFuture<U>()
        addCompletionHandler { value, failure ->
            if (failure != null) {
                dependent.propagateFailure(failure)
            } else {
                try {
                    dependent.complete(action(value as T))
                } catch (thrown: Throwable) {
                    dependent.completeExceptionally(thrown)
                }
            }
        }
        return dependent
    }

    public override fun <U> thenCompose(action: (T) -> CompletionStage<U>): CompletableFuture<U> {
        val dependent = CompletableFuture<U>()
        addCompletionHandler { value, failure ->
            if (failure != null) {
                dependent.propagateFailure(failure)
            } else {
                try {
                    action(value as T).toCompletableFuture().addCompletionHandler { composedValue, composedFailure ->
                        if (composedFailure == null) {
                            dependent.complete(composedValue as U)
                        } else {
                            dependent.propagateFailure(composedFailure)
                        }
                    }
                } catch (thrown: Throwable) {
                    dependent.completeExceptionally(thrown)
                }
            }
        }
        return dependent
    }

    public override fun whenComplete(action: (T?, Throwable?) -> Unit): CompletableFuture<T> {
        val dependent = CompletableFuture<T>()
        addCompletionHandler { value, failure ->
            try {
                action(value, failure)
                if (failure == null) {
                    dependent.complete(value as T)
                } else {
                    dependent.propagateFailure(failure)
                }
            } catch (thrown: Throwable) {
                dependent.completeExceptionally(thrown)
            }
        }
        return dependent
    }

    private fun addCompletionHandler(handler: (T?, Throwable?) -> Unit) {
        if (isCompleted) {
            handler(result, exception)
        } else {
            completionHandlers.add(handler)
        }
    }

    private fun notifyCompletionHandlers() {
        val handlers = completionHandlers.toList()
        completionHandlers.clear()
        for (handler in handlers) {
            handler(result, exception)
        }
    }

    private fun propagateFailure(failure: Throwable) {
        if (failure is CancellationException) {
            cancel(false)
        } else {
            completeExceptionally(failure)
        }
    }

    public companion object {
        public fun <U> completedFuture(value: U): CompletableFuture<U> {
            val cf = CompletableFuture<U>()
            cf.complete(value)
            return cf
        }

        public fun <U> failedFuture(ex: Throwable): CompletableFuture<U> {
            val cf = CompletableFuture<U>()
            cf.completeExceptionally(ex)
            return cf
        }

        @Suppress("UNCHECKED_CAST")
        public fun allOf(vararg futures: CompletableFuture<*>): CompletableFuture<Unit> {
            val result = CompletableFuture<Unit>()
            if (futures.isEmpty()) {
                result.complete(Unit)
                return result
            }

            var remaining = futures.size
            var firstFailure: Throwable? = null
            var cancelled = false
            for (future in futures) {
                val erasedFuture = future as CompletableFuture<Any?>
                erasedFuture.addCompletionHandler { _, failure ->
                    if (failure != null && firstFailure == null) {
                        firstFailure = failure
                        cancelled = erasedFuture.isCancelled
                    }
                    remaining -= 1
                    if (remaining == 0) {
                        val terminalFailure = firstFailure
                        if (terminalFailure == null) {
                            result.complete(Unit)
                        } else if (cancelled) {
                            result.cancel(false)
                        } else {
                            result.completeExceptionally(terminalFailure)
                        }
                    }
                }
            }
            return result
        }

        @Suppress("UNCHECKED_CAST")
        public fun anyOf(vararg futures: CompletableFuture<*>): CompletableFuture<Any?> {
            val result = CompletableFuture<Any?>()
            for (future in futures) {
                val erasedFuture = future as CompletableFuture<Any?>
                erasedFuture.addCompletionHandler { value, failure ->
                    if (failure == null) {
                        result.complete(value)
                    } else if (erasedFuture.isCancelled) {
                        result.cancel(false)
                    } else {
                        result.completeExceptionally(failure)
                    }
                }
            }
            return result
        }
    }
}
