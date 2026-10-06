// KUU-1291: mirror the atomicfu API without requiring the external library.
class AtomicRef<T>(var value: T) {
    fun compareAndSet(expect: T, update: T): Boolean {
        if (value != expect) return false
        value = update
        return true
    }
}

fun <T> atomic(value: T): AtomicRef<T> = AtomicRef(value)

fun interface DisposableHandle {
    fun dispose()
}

class C {
    private val closeHandler = atomic<((Throwable?) -> Unit)?>(null)

    fun reg(handler: (Throwable?) -> Unit): DisposableHandle {
        if (!closeHandler.compareAndSet(null, handler)) throw Error()
        return DisposableHandle { closeHandler.compareAndSet(handler, null) }
    }

    fun isEmpty(): Boolean = closeHandler.value == null
}

fun main() {
    val channel = C()
    val handle = channel.reg { println("unexpected handler invocation") }
    println(channel.isEmpty())
    handle.dispose()
    println(channel.isEmpty())
    handle.dispose()
    println(channel.isEmpty())
}
