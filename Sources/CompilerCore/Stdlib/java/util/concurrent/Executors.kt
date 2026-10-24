@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import java.lang.Runnable
import kotlinx.atomicfu.locks.ParkingHandle
import kotlinx.atomicfu.locks.ParkingSupport
import kotlinx.atomicfu.locks.SynchronizedObject
import platform.Foundation.NSThread

// KUU-3059: java.util.concurrent.Executors over platform.Foundation.NSThread.
// Workers are spawned lazily on the first submitted task so an unused
// executor costs no thread; waiters (worker-idle and awaitTermination) park
// on their atomicfu handles.

public object Executors {
    public fun newSingleThreadExecutor(): ExecutorService = PooledExecutorService(1)

    public fun newFixedThreadPool(nThreads: Int): ExecutorService {
        if (nThreads <= 0) throw IllegalArgumentException("nThreads <= 0")
        return PooledExecutorService(nThreads)
    }

    public fun newCachedThreadPool(): ExecutorService = CachedThreadExecutorService()

    public fun <T> callable(task: Runnable, result: T): Callable<T> = Callable {
        task.run()
        result
    }

    public fun callable(task: Runnable): Callable<Any?> = callable(task, null)

    public fun unconfigurableExecutorService(executor: ExecutorService): ExecutorService =
        executor
}

private class PooledExecutorService(private val workerCount: Int) : ExecutorService {
    private val guard = SynchronizedObject()
    private val queue = ArrayDeque<Runnable>()
    private val workerHandles = ArrayList<ParkingHandle>()
    private val terminationWaiters = ArrayList<ParkingHandle>()
    private var shutdown = false
    private var terminated = false
    private var started = false
    private var exitedWorkers = 0

    override fun execute(command: Runnable) {
        val wake: List<ParkingHandle>
        guard.lock()
        try {
            if (shutdown) throw RejectedExecutionException("Executor is shutdown")
            queue.addLast(command)
            ensureStartedLocked()
            wake = workerHandles.take(1)
        } finally {
            guard.unlock()
        }
        jucUnparkAll(wake)
    }

    private fun ensureStartedLocked() {
        if (started) return
        started = true
        var spawned = 0
        while (spawned < workerCount) {
            val thread = NSThread { workerLoop() }
            spawned += 1
            thread.start()
        }
    }

    private fun workerLoop() {
        val handle = ParkingSupport.currentThreadHandle()
        guard.lock()
        try {
            workerHandles.add(handle)
        } finally {
            guard.unlock()
        }
        try {
            while (true) {
                var task: Runnable? = null
                guard.lock()
                try {
                    if (queue.isNotEmpty()) {
                        task = queue.removeFirst()
                    }
                } finally {
                    guard.unlock()
                }
                if (task != null) {
                    task.run()
                    continue
                }
                val keepGoing: Boolean
                guard.lock()
                try {
                    when {
                        shutdown && queue.isEmpty() -> return
                        queue.isNotEmpty() -> keepGoing = true
                        else -> keepGoing = false
                    }
                } finally {
                    guard.unlock()
                }
                if (keepGoing) continue
                jucPark(-1L)
            }
        } finally {
            workerExited()
        }
    }

    private fun workerExited() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            exitedWorkers += 1
            if (!shutdown || exitedWorkers < workerCount) return
            terminated = true
            release = ArrayList(terminationWaiters)
            terminationWaiters.clear()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    override fun shutdown() {
        val wake: List<ParkingHandle>
        val termRelease: List<ParkingHandle>
        guard.lock()
        try {
            if (shutdown) return
            shutdown = true
            wake = ArrayList(workerHandles)
            // Never started: no worker exists to mark termination, so flip it
            // here. Started workers flip it themselves in workerExited().
            if (!started) {
                terminated = true
                termRelease = ArrayList(terminationWaiters)
                terminationWaiters.clear()
            } else {
                termRelease = emptyList()
            }
        } finally {
            guard.unlock()
        }
        jucUnparkAll(wake)
        jucUnparkAll(termRelease)
    }

    override fun shutdownNow(): List<Runnable> {
        val pending = ArrayList<Runnable>()
        val wake: List<ParkingHandle>
        guard.lock()
        try {
            shutdown = true
            while (queue.isNotEmpty()) pending.add(queue.removeFirst())
            wake = ArrayList(workerHandles)
        } finally {
            guard.unlock()
        }
        jucUnparkAll(wake)
        return pending
    }

    override val isShutdown: Boolean
        get() {
            guard.lock()
            try {
                return shutdown
            } finally {
                guard.unlock()
            }
        }

    override val isTerminated: Boolean
        get() {
            guard.lock()
            try {
                return terminated
            } finally {
                guard.unlock()
            }
        }

    override fun awaitTermination(timeout: Long, unit: TimeUnit): Boolean {
        val deadline = jucDeadlineNanos(unit.toNanos(timeout))
        val handle = ParkingSupport.currentThreadHandle()
        guard.lock()
        try {
            if (terminated) return true
            terminationWaiters.add(handle)
        } finally {
            guard.unlock()
        }
        try {
            while (true) {
                if (terminated) return true
                val left = jucNanosLeft(deadline)
                if (left <= 0L) return false
                jucPark(if (deadline < 0L) -1L else left)
            }
        } finally {
            guard.lock()
            try {
                terminationWaiters.remove(handle)
            } finally {
                guard.unlock()
            }
        }
    }

    override fun <T> submit(task: Callable<T>): Future<T> {
        val future = FutureTask(task)
        execute(future)
        return future
    }

    override fun submit(task: Runnable): Future<*> {
        val future = FutureTask<Unit>(Callable {
            task.run()
        })
        execute(future)
        return future
    }

    override fun <T> submit(task: Runnable, result: T): Future<T> {
        val future = FutureTask(Callable {
            task.run()
            result
        })
        execute(future)
        return future
    }

    override fun <T> invokeAll(tasks: Collection<Callable<T>>): List<Future<T>> {
        val futures = tasks.map { submit(it) }
        for (future in futures) future.get()
        return futures
    }

    override fun <T> invokeAny(tasks: Collection<Callable<T>>): T {
        if (tasks.isEmpty()) throw IllegalArgumentException("tasks is empty")
        val futures = tasks.map { submit(it) }
        var failure: Throwable? = null
        for (future in futures) {
            try {
                return future.get()
            } catch (thrown: ExecutionException) {
                failure = thrown
            }
        }
        throw ExecutionException(null as String?, failure)
    }
}

// Cached-pool approximation: each submitted task gets its own NSThread,
// matching the JVM cached pool's unbounded-growth contract minus idle reuse.
private class CachedThreadExecutorService : ExecutorService {
    private val guard = SynchronizedObject()
    private val terminationWaiters = ArrayList<ParkingHandle>()
    private var shutdown = false
    private var running = 0

    override fun execute(command: Runnable) {
        guard.lock()
        try {
            if (shutdown) throw RejectedExecutionException("Executor is shutdown")
            running += 1
        } finally {
            guard.unlock()
        }
        NSThread {
            try {
                command.run()
            } finally {
                taskFinished()
            }
        }.start()
    }

    private fun taskFinished() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            running -= 1
            if (!shutdown || running > 0) return
            release = ArrayList(terminationWaiters)
            terminationWaiters.clear()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    override fun shutdown() {
        val release: List<ParkingHandle>
        guard.lock()
        try {
            if (shutdown) return
            shutdown = true
            if (running > 0) return
            release = ArrayList(terminationWaiters)
            terminationWaiters.clear()
        } finally {
            guard.unlock()
        }
        jucUnparkAll(release)
    }

    override fun shutdownNow(): List<Runnable> {
        shutdown()
        return emptyList()
    }

    override val isShutdown: Boolean
        get() {
            guard.lock()
            try {
                return shutdown
            } finally {
                guard.unlock()
            }
        }

    override val isTerminated: Boolean
        get() {
            guard.lock()
            try {
                return shutdown && running == 0
            } finally {
                guard.unlock()
            }
        }

    override fun awaitTermination(timeout: Long, unit: TimeUnit): Boolean {
        val deadline = jucDeadlineNanos(unit.toNanos(timeout))
        val handle = ParkingSupport.currentThreadHandle()
        guard.lock()
        try {
            if (isTerminatedUnlocked()) return true
            terminationWaiters.add(handle)
        } finally {
            guard.unlock()
        }
        try {
            while (true) {
                guard.lock()
                try {
                    if (isTerminatedUnlocked()) return true
                } finally {
                    guard.unlock()
                }
                val left = jucNanosLeft(deadline)
                if (left <= 0L) return false
                jucPark(if (deadline < 0L) -1L else left)
            }
        } finally {
            guard.lock()
            try {
                terminationWaiters.remove(handle)
            } finally {
                guard.unlock()
            }
        }
    }

    private fun isTerminatedUnlocked(): Boolean = shutdown && running == 0

    override fun <T> submit(task: Callable<T>): Future<T> {
        val future = FutureTask(task)
        execute(future)
        return future
    }

    override fun submit(task: Runnable): Future<*> {
        val future = FutureTask<Unit>(Callable {
            task.run()
        })
        execute(future)
        return future
    }

    override fun <T> submit(task: Runnable, result: T): Future<T> {
        val future = FutureTask(Callable {
            task.run()
            result
        })
        execute(future)
        return future
    }

    override fun <T> invokeAll(tasks: Collection<Callable<T>>): List<Future<T>> {
        val futures = tasks.map { submit(it) }
        for (future in futures) future.get()
        return futures
    }

    override fun <T> invokeAny(tasks: Collection<Callable<T>>): T {
        if (tasks.isEmpty()) throw IllegalArgumentException("tasks is empty")
        val futures = tasks.map { submit(it) }
        var failure: Throwable? = null
        for (future in futures) {
            try {
                return future.get()
            } catch (thrown: ExecutionException) {
                failure = thrown
            }
        }
        throw ExecutionException(null as String?, failure)
    }
}
