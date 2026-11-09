@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import java.util.function.Supplier
import java.lang.Runnable
import java.util.Timer
import java.util.TimerTask
import kotlinx.atomicfu.locks.ParkingSupport
import kotlin.coroutines.cancellation.CancellationException
import platform.Foundation.NSThread
import kotlin.system.System

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
    public fun isCompletedExceptionally(): Boolean = isCompleted && exception != null

    @Suppress("UNCHECKED_CAST")
    public override fun get(): T {
        if (!isCompleted) {
            val handle = ParkingSupport.currentThreadHandle()
            addCompletionHandler { _, _ -> ParkingSupport.unpark(handle) }
            while (!isCompleted) jucPark(-1L)
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
    public override operator fun get(timeout: Long, unit: TimeUnit): T {
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

    public override fun thenRun(action: Runnable): CompletableFuture<Unit> = thenAccept { action.run() }

    public override fun <U> thenApplyAsync(action: (T) -> U): CompletableFuture<U> = thenApplyAsync(action, null)

    public override fun <U> thenApplyAsync(action: (T) -> U, executor: Executor?): CompletableFuture<U> =
        asyncDependent(executor, action)

    public override fun thenAcceptAsync(action: (T) -> Unit): CompletableFuture<Unit> = thenAcceptAsync(action, null)

    public override fun thenAcceptAsync(action: (T) -> Unit, executor: Executor?): CompletableFuture<Unit> =
        thenApplyAsync({ value -> action(value); Unit }, executor)

    public override fun thenRunAsync(action: Runnable): CompletableFuture<Unit> = thenRunAsync(action, null)

    public override fun thenRunAsync(action: Runnable, executor: Executor?): CompletableFuture<Unit> =
        thenAcceptAsync({ action.run() }, executor)

    public override fun <U> thenComposeAsync(action: (T) -> CompletionStage<U>): CompletableFuture<U> =
        thenComposeAsync(action, null)

    public override fun <U> thenComposeAsync(
        action: (T) -> CompletionStage<U>,
        executor: Executor?,
    ): CompletableFuture<U> {
        val dependent = CompletableFuture<U>()
        addCompletionHandler { value, failure ->
            if (failure != null) {
                dependent.propagateFailure(failure)
            } else {
                dependent.dispatch(executor) {
                    try {
                        action(value as T).toCompletableFuture().addCompletionHandler { composedValue, composedFailure ->
                            if (composedFailure == null) dependent.complete(composedValue as U)
                            else dependent.propagateFailure(composedFailure)
                        }
                    } catch (thrown: Throwable) {
                        dependent.completeExceptionally(thrown)
                    }
                }
            }
        }
        return dependent
    }

    public override fun <U> handle(action: (T?, Throwable?) -> U): CompletableFuture<U> {
        val dependent = CompletableFuture<U>()
        addCompletionHandler { value, failure ->
            try {
                dependent.complete(action(value, failure))
            } catch (thrown: Throwable) {
                dependent.completeExceptionally(thrown)
            }
        }
        return dependent
    }

    public override fun <U> handleAsync(action: (T?, Throwable?) -> U): CompletableFuture<U> = handleAsync(action, null)

    public override fun <U> handleAsync(action: (T?, Throwable?) -> U, executor: Executor?): CompletableFuture<U> {
        val dependent = CompletableFuture<U>()
        addCompletionHandler { value, failure ->
            dependent.dispatch(executor) {
                try {
                    dependent.complete(action(value, failure))
                } catch (thrown: Throwable) {
                    dependent.completeExceptionally(thrown)
                }
            }
        }
        return dependent
    }

    public override fun exceptionally(action: (Throwable) -> T): CompletableFuture<T> {
        val dependent = CompletableFuture<T>()
        addCompletionHandler { value, failure ->
            if (failure == null) dependent.complete(value as T)
            else try {
                dependent.complete(action(failure))
            } catch (thrown: Throwable) {
                dependent.completeExceptionally(thrown)
            }
        }
        return dependent
    }

    public override fun exceptionallyAsync(action: (Throwable) -> T): CompletableFuture<T> = exceptionallyAsync(action, null)

    public override fun exceptionallyAsync(action: (Throwable) -> T, executor: Executor?): CompletableFuture<T> {
        val dependent = CompletableFuture<T>()
        addCompletionHandler { value, failure ->
            if (failure == null) dependent.complete(value as T)
            else dependent.dispatch(executor) {
                try {
                    dependent.complete(action(failure))
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

    public override fun whenCompleteAsync(action: (T?, Throwable?) -> Unit): CompletableFuture<T> = whenCompleteAsync(action, null)

    public override fun whenCompleteAsync(action: (T?, Throwable?) -> Unit, executor: Executor?): CompletableFuture<T> {
        val dependent = CompletableFuture<T>()
        addCompletionHandler { value, failure ->
            dependent.dispatch(executor) {
                try {
                    action(value, failure)
                    if (failure == null) dependent.complete(value as T) else dependent.propagateFailure(failure)
                } catch (thrown: Throwable) {
                    dependent.completeExceptionally(thrown)
                }
            }
        }
        return dependent
    }

    public override fun thenAccept(action: (T) -> Unit): CompletableFuture<Unit> {
        val dependent = CompletableFuture<Unit>()
        addCompletionHandler { value, failure ->
            if (failure != null) {
                dependent.propagateFailure(failure)
            } else {
                try {
                    action(value as T)
                    dependent.complete(Unit)
                } catch (thrown: Throwable) {
                    dependent.completeExceptionally(thrown)
                }
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

    private fun <U> asyncDependent(executor: Executor?, action: (T) -> U): CompletableFuture<U> {
        val dependent = CompletableFuture<U>()
        addCompletionHandler { value, failure ->
            if (failure != null) dependent.propagateFailure(failure)
            else dependent.dispatch(executor) {
                try {
                    dependent.complete(action(value as T))
                } catch (thrown: Throwable) {
                    dependent.completeExceptionally(thrown)
                }
            }
        }
        return dependent
    }

    private fun dispatch(executor: Executor?, action: () -> Unit) {
        try {
            if (executor != null) executor.execute(Runnable { action() })
            else NSThread { action() }.start()
        } catch (thrown: Throwable) {
            completeExceptionally(thrown)
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

    public fun completeAsync(supplier: Supplier<T>): CompletableFuture<T> = completeAsync(supplier, null)

    public fun completeAsync(supplier: Supplier<T>, executor: Executor?): CompletableFuture<T> {
        dispatch(executor) {
            try {
                complete(supplier.get())
            } catch (thrown: Throwable) {
                completeExceptionally(thrown)
            }
        }
        return this
    }

    public fun orTimeout(timeout: Long, unit: TimeUnit): CompletableFuture<T> {
        val timer = Timer("CompletableFutureTimeout", true)
        val task = object : TimerTask() {
            override fun run() {
                completeExceptionally(TimeoutException())
                timer.cancel()
            }
        }
        if (!isCompleted) {
            timer.schedule(task, maxOf(0L, unit.toMillis(timeout)))
            addCompletionHandler { _, _ ->
                task.cancel()
                timer.cancel()
            }
        } else {
            timer.cancel()
        }
        return this
    }

    public fun completeOnTimeout(value: T, timeout: Long, unit: TimeUnit): CompletableFuture<T> {
        val timer = Timer("CompletableFutureTimeout", true)
        val task = object : TimerTask() {
            override fun run() {
                complete(value)
                timer.cancel()
            }
        }
        if (!isCompleted) {
            timer.schedule(task, maxOf(0L, unit.toMillis(timeout)))
            addCompletionHandler { _, _ ->
                task.cancel()
                timer.cancel()
            }
        } else {
            timer.cancel()
        }
        return this
    }

    public fun copy(): CompletableFuture<T> {
        val copy = CompletableFuture<T>()
        addCompletionHandler { value, failure ->
            if (failure == null) copy.complete(value as T) else copy.propagateFailure(failure)
        }
        return copy
    }

    public fun minimalCompletionStage(): CompletionStage<T> = this

    public fun getNow(valueIfAbsent: T): T = if (isCompleted) get() else valueIfAbsent

    public fun resultNow(): T {
        if (!isCompleted || exception != null) throw IllegalStateException("No normal result is available")
        return result as T
    }

    public fun exceptionNow(): Throwable {
        if (!isCompleted || exception == null) throw IllegalStateException("No exceptional result is available")
        return exception as Throwable
    }

    public fun obtrudeValue(value: T) {
        result = value
        exception = null
        isCancelledFlag = false
        isCompleted = true
    }

    public fun obtrudeException(ex: Throwable) {
        result = null
        exception = ex
        isCancelledFlag = false
        isCompleted = true
    }

    public companion object {
        public fun <U> supplyAsync(supplier: Supplier<U>): CompletableFuture<U> {
            val future = CompletableFuture<U>()
            NSThread {
                try {
                    future.complete(supplier.get())
                } catch (thrown: Throwable) {
                    future.completeExceptionally(thrown)
                }
            }.start()
            return future
        }

        public fun <U> supplyAsync(supplier: Supplier<U>, executor: Executor): CompletableFuture<U> {
            val future = CompletableFuture<U>()
            try {
                executor.execute(Runnable {
                    try { future.complete(supplier.get()) }
                    catch (thrown: Throwable) { future.completeExceptionally(thrown) }
                })
            } catch (thrown: Throwable) {
                future.completeExceptionally(thrown)
            }
            return future
        }

        public fun runAsync(action: Runnable): CompletableFuture<Unit> {
            val future = CompletableFuture<Unit>()
            NSThread {
                try { action.run(); future.complete(Unit) }
                catch (thrown: Throwable) { future.completeExceptionally(thrown) }
            }.start()
            return future
        }

        public fun runAsync(action: Runnable, executor: Executor): CompletableFuture<Unit> {
            val future = CompletableFuture<Unit>()
            try {
                executor.execute(Runnable {
                    try { action.run(); future.complete(Unit) }
                    catch (thrown: Throwable) { future.completeExceptionally(thrown) }
                })
            } catch (thrown: Throwable) {
                future.completeExceptionally(thrown)
            }
            return future
        }

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
