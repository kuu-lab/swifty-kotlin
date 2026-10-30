package java.lang

import java.util.concurrent.TimeUnit
import java.util.concurrent.CountDownLatch
import kotlinx.atomicfu.locks.SynchronizedObject
import platform.Foundation.NSThread
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_thread_report_uncaught")
private external fun threadReportUncaught(exception: Throwable): Unit

@KsSymbolName("__kk_thread_non_daemon_start")
private external fun threadNonDaemonStart(): Unit

@KsSymbolName("__kk_thread_non_daemon_finish")
private external fun threadNonDaemonFinish(): Unit

@KsSymbolName("__kk_thread_local_new")
private external fun threadCurrentKey(): Long

@KsSymbolName("__kk_thread_local_value")
private external fun threadCurrentValue(key: Long): Any?

@KsSymbolName("__kk_thread_local_store")
private external fun threadSetCurrent(key: Long, value: Any?): Unit

@KsSymbolName("__kk_thread_local_remove")
private external fun threadRemoveCurrent(key: Long): Unit

public class Thread private constructor(
    private val target: Runnable?,
    initialName: String?,
    currentThread: kotlin.Boolean
) {
    private val threadId: kotlin.Long = allocateId()
    public var name: String = initialName ?: allocateName()
    public var isDaemon: kotlin.Boolean = false
        set(value) {
            stateLock.lock()
            try {
                if (started) throw IllegalThreadStateException("Thread has already been started")
                field = value
            } finally { stateLock.unlock() }
        }
    public var priority: Int = 5
        set(value) {
            if (value < 1 || value > 10) throw IllegalArgumentException("Invalid thread priority")
            field = value
        }
    public var contextClassLoader: ClassLoader? = null
    private val stateLock = SynchronizedObject()
    private val finished = CountDownLatch(1)
    private var started: kotlin.Boolean = currentThread
    private var alive: kotlin.Boolean = currentThread
    public val isAlive: kotlin.Boolean
        get() {
            stateLock.lock()
            try { return alive } finally { stateLock.unlock() }
        }

    private fun hasStarted(): kotlin.Boolean {
        stateLock.lock()
        try { return started } finally { stateLock.unlock() }
    }

    init {
        if (!currentThread) {
            val parent = currentThread()
            isDaemon = parent.isDaemon
            priority = parent.priority
            contextClassLoader = parent.contextClassLoader
        } else {
            contextClassLoader = getSystemClassLoader()
        }
    }

    public constructor() : this(null, null, false)

    public constructor(target: Runnable) : this(target, null, false)

    public constructor(name: String) : this(null, name, false)

    public constructor(target: Runnable, name: String) : this(target, name, false)

    public val id: kotlin.Long
        get() = threadId

    public fun run() {
        target?.run()
    }

    public fun start() {
        stateLock.lock()
        try {
            if (started) throw IllegalThreadStateException("Thread has already been started")
            started = true
            alive = true
        } finally {
            stateLock.unlock()
        }
        countLock.lock()
        try { activeThreadCount += 1 } finally { countLock.unlock() }
        val nonDaemon = !isDaemon
        if (nonDaemon) threadNonDaemonStart()
        val thread = NSThread {
            threadSetCurrent(currentKey, this)
            try {
                run()
            } catch (exception: Throwable) {
                threadReportUncaught(exception)
            } finally {
                threadRemoveCurrent(currentKey)
                stateLock.lock()
                try { alive = false } finally { stateLock.unlock() }
                countLock.lock()
                try { activeThreadCount -= 1 } finally { countLock.unlock() }
                finished.countDown()
                if (nonDaemon) threadNonDaemonFinish()
            }
        }
        thread.name = name
        thread.start()
    }

    public fun join() {
        if (hasStarted()) finished.await()
    }

    public fun join(millis: kotlin.Long) {
        if (millis < 0L) throw IllegalArgumentException("timeout value is negative")
        if (!hasStarted()) return
        if (millis == 0L) finished.await() else finished.await(millis, TimeUnit.MILLISECONDS)
    }

    public fun join(millis: kotlin.Long, nanos: Int) {
        if (millis < 0L || nanos < 0 || nanos > 999_999) {
            throw IllegalArgumentException("timeout value is out of range")
        }
        if (!hasStarted()) return
        if (millis == 0L && nanos == 0) finished.await()
        else {
            val rounded = if (nanos > 0 && millis < Long.MAX_VALUE) millis + 1L else millis
            finished.await(rounded, TimeUnit.MILLISECONDS)
        }
    }

    public companion object {
        private val countLock = SynchronizedObject()
        private var nextId: kotlin.Long = 1L
        private var nextName: Int = 0
        private var activeThreadCount: Int = 1
        private val currentKey = threadCurrentKey()
        private val current = Thread(null, "main", true)

        private fun allocateId(): kotlin.Long {
            countLock.lock()
            try {
                val result = nextId
                nextId += 1L
                return result
            } finally { countLock.unlock() }
        }

        private fun allocateName(): String {
            countLock.lock()
            try {
                val result = "Thread-${nextName}"
                nextName += 1
                return result
            } finally { countLock.unlock() }
        }

        public fun currentThread(): Thread {
            val existing = threadCurrentValue(currentKey) as? Thread
            if (existing != null) return existing
            val platformName = NSThread.currentThread.name
            if (platformName == "main") {
                threadSetCurrent(currentKey, current)
                return current
            }
            val initialName = if (platformName != null && platformName.isNotEmpty()) platformName else null
            val attached = Thread(null, initialName, true)
            threadSetCurrent(currentKey, attached)
            return attached
        }

        public fun sleep(millis: kotlin.Long) {
            if (millis < 0L) throw IllegalArgumentException("timeout value is negative")
            TimeUnit.MILLISECONDS.sleep(millis)
        }

        public fun sleep(millis: kotlin.Long, nanos: Int) {
            if (millis < 0L || nanos < 0 || nanos > 999_999) {
                throw IllegalArgumentException("timeout value is out of range")
            }
            if (millis > 0L) TimeUnit.MILLISECONDS.sleep(millis)
            if (nanos > 0) TimeUnit.NANOSECONDS.sleep(nanos.toLong())
        }

        public fun yield() {}

        public fun activeCount(): Int {
            countLock.lock()
            try { return activeThreadCount } finally { countLock.unlock() }
        }
    }
}
