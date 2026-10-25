package java.lang

import java.util.concurrent.TimeUnit

public class Thread private constructor(
    private val target: Runnable?,
    initialName: String?,
    currentThread: Boolean
) {
    private val threadId: kotlin.Long = allocateId()
    public var name: String = initialName ?: allocateName()
    private var started: Boolean = currentThread
    public var isAlive: Boolean = currentThread
        private set

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
        if (started) throw IllegalThreadStateException("Thread has already been started")
        started = true
        isAlive = true
        activeThreadCount += 1
        try {
            run()
        } finally {
            isAlive = false
            activeThreadCount -= 1
        }
    }

    public fun join() {}

    public fun join(millis: kotlin.Long) {
        if (millis < 0L) throw IllegalArgumentException("timeout value is negative")
    }

    public fun join(millis: kotlin.Long, nanos: Int) {
        if (millis < 0L || nanos < 0 || nanos > 999_999) {
            throw IllegalArgumentException("timeout value is out of range")
        }
    }

    public companion object {
        private var nextId: kotlin.Long = 1L
        private var nextName: Int = 0
        private var activeThreadCount: Int = 1
        private val current = Thread(null, "main", true)

        private fun allocateId(): kotlin.Long {
            val result = nextId
            nextId += 1L
            return result
        }

        private fun allocateName(): String {
            val result = "Thread-${nextName}"
            nextName += 1
            return result
        }

        public fun currentThread(): Thread = current

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

        public fun activeCount(): Int = activeThreadCount
    }
}
