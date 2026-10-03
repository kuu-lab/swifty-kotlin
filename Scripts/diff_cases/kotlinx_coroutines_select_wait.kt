import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*
import kotlinx.coroutines.selects.*
import kotlinx.coroutines.sync.*

fun main() = runBlocking {
    val channel = Channel<Int>(1)
    val sender = launch {
        yield()
        channel.send(7)
    }
    println(select<String> { channel.onReceive { "received:$it" } })
    println(select<String> { sender.onJoin { "joined" } })
    val deferred = async { 42 }
    println(select<String> { deferred.onAwait { "awaited:$it" } })
    val mutex = Mutex()
    println(select<String> {
        mutex.onLock { "locked" }
        onTimeout(0L) { "unexpected" }
    })
    println(mutex.isLocked)
    mutex.unlock()
    mutex.lock()
    println(selectUnbiased<String> {
        mutex.onLock { "unexpected" }
        onTimeout(1L) { "timeout" }
    })
    mutex.unlock()
    val strings = Channel<String>(1)
    strings.send("value")
    println(select<String> { strings.onReceive { it + "!" } })
    val lazyDeferred = async(start = CoroutineStart.LAZY) { 9 }
    println(select<String> { lazyDeferred.onAwait { "lazy:$it" } })
    val clause: SelectClause1<Any?> = strings.onReceive
    strings.send("clause")
    println(select<String> { clause { "property:$it" } })
    try {
        select<String> { onTimeout(0L) { throw IllegalStateException("block") } }
    } catch (failure: IllegalStateException) {
        println("caught")
    }
    println(select<String> { onTimeout(0L) {
        yield()
        "suspended"
    } })
    // KUU-962: R must flow from the clause callback's return type into
    // SelectBuilder<R> -- untyped select, expected-type, and inferred select
    // over a non-String element all rely on that connection.
    strings.send("infer")
    println(select { strings.onReceive { "infer:$it" } })
    strings.send("exp")
    val expectedType: String = select { strings.onReceive { "exp:$it" } }
    println(expectedType)
    channel.send(11)
    println(select { channel.onReceive { "nint:$it" } })
    println("done")
}
