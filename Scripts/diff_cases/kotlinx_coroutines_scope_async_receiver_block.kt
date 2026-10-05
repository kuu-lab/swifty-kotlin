import kotlinx.coroutines.*

// KUU-1198: `CoroutineScope.async`'s block is a
// `suspend CoroutineScope.() -> T` — receiver-bearing suspend function values
// stored in a variable, forwarded through another call, or passed as a named
// argument must all bind the receiver scope as `this` and captures correctly.
fun asyncValue(scope: CoroutineScope, block: suspend CoroutineScope.() -> Int): Deferred<Int> =
    scope.async(block = block)

fun main() = runBlocking {
    val bonus = 7
    val block: suspend CoroutineScope.() -> Int = { bonus + 23 }
    println(asyncValue(this, block).await())
    println(this.async(block = block).await())
    println(this.async { bonus + 23 }.await())
    println(this.async(start = CoroutineStart.LAZY) { bonus + 30 }.await())
    val viaValue = asyncValue(this, block)
    val literal = this.async { bonus + 23 }
    println(viaValue.await() + literal.await())
    // Unqualified member-on-implicit-receiver shapes: an explicit Deferred<T>
    // annotation routes through the boxed path; a stored receiver-bearing
    // value resolves to the function-value adapter.
    val t1: Deferred<Int> = async { 11 }
    println(t1.await())
    val t2: Deferred<Int> = async { 22 }
    println(t2.await())
    val stored: Deferred<Int> = async(block = block)
    println(stored.await())
    println(async(block = block).await())
}
