@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import java.lang.Runnable
import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.coroutines.CancellationException
import kotlin.concurrent.Volatile

// KUU-3059: java.util.concurrent.RunnableFuture / FutureTask — the
// Runnable+Future carrier that executors run and callers block on. get()
// parks the waiting thread on its per-thread atomicfu handle until run()
// finishes; cancel() never interrupts (no thread interruption exists yet).

public interface RunnableFuture<V> : Runnable, Future<V> {
    public override fun run()
}

public open class FutureTask<V> : RunnableFuture<V> {
    private val callable: Callable<V>
    private val guard = SynchronizedObject()
    private val waiters = ArrayList<ParkingHandle>()

    // 0 = not run, 1 = result, 2 = exception, 3 = cancelled
    @Volatile
    private var state = 0
    private var result: V? = null
    private var failure: Throwable? = null

    public constructor(callable: Callable<V>) {
        this.callable = callable
    }

    public constructor(runnable: Runnable, result: V) {
        this.callable = Callable {
            runnable.run()
            result
        }
    }

    override fun run() {
        guard.lock()
        try {
            if (state != 0) return
        } finally {
            guard.unlock()
        }
        try {
            val value = callable.call()
            guard.lock()
            try {
                // A cancel racing the callable's completion wins — but the
                // waiters still need releasing below.
                if (state == 0) {
                    result = value
                    state = 1
                }
            } finally {
                guard.unlock()
            }
        } catch (thrown: Throwable) {
            guard.lock()
            try {
                if (state == 0) {
                    failure = thrown
                    state = 2
                }
            } finally {
                guard.unlock()
            }
        }
        releaseWaiters()
    }

    override val isDone: Boolean get() = state != 0

    override val isCancelled: Boolean get() = state == 3

    override fun cancel(mayInterruptIfRunning: Boolean): Boolean {
        guard.lock()
        try {
            if (state != 0) return false
            state = 3
        } finally {
            guard.unlock()
        }
        releaseWaiters()
        return true
    }

    override fun get(): V = getNanos(-1L)

    override fun get(timeout: Long, unit: TimeUnit): V =
        getNanos(unit.toNanos(timeout))

    private fun getNanos(nanos: Long): V {
        if (!waitDone(nanos)) throw TimeoutException()
        when (state) {
            1 -> return unwrapResult()
            2 -> throw ExecutionException(null, failure)
            3 -> throw CancellationException("FutureTask was cancelled")
            else -> throw IllegalStateException("unreachable FutureTask state")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun unwrapResult(): V = result as V

    private fun waitDone(nanos: Long): Boolean {
        if (state != 0) return true
        val handle = ParkingSupport.currentThreadHandle()
        guard.lock()
        try {
            if (state != 0) return true
            waiters.add(handle)
        } finally {
            guard.unlock()
        }
        val deadline = jucDeadlineNanos(nanos)
        try {
            while (true) {
                if (state != 0) return true
                val left = jucNanosLeft(deadline)
                if (left <= 0L) return false
                jucPark(if (deadline < 0L) -1L else left)
            }
        } finally {
            guard.lock()
            try {
                waiters.remove(handle)
            } finally {
                guard.unlock()
            }
        }
    }

    private fun releaseWaiters() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            release = ArrayList(waiters)
            waiters.clear()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    override fun toString(): String = when (state) {
        0 -> "FutureTask[Not completed]"
        1 -> "FutureTask[Completed normally]"
        2 -> "FutureTask[Completed exceptionally: $failure]"
        else -> "FutureTask[Cancelled]"
    }
}
