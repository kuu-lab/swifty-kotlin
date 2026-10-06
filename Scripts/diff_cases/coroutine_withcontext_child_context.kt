// KUU-1398: `withContext(overrides)` must run its block under a child context —
// `parent + overrides + a fresh child Job`. The ambient `coroutineContext`
// inside the block used to be content-identical to the outer one (no override
// elements, same Job).
import kotlinx.coroutines.*
import kotlin.coroutines.*

suspend fun readInside(outer: CoroutineContext) {
    // A nested suspend call observes the same child context.
    println(coroutineContext === outer)
    println(coroutineContext[CoroutineName]?.name)
    println(coroutineContext.job === outer.job)
}

fun main() = runBlocking {
    val outer = coroutineContext
    withContext(CoroutineName("wc")) {
        println(coroutineContext === outer)
        println(coroutineContext[CoroutineName]?.name)
        println(coroutineContext.job === outer.job)
        readInside(outer)
    }
    // The outer context is restored after the block.
    println(coroutineContext === outer)
    println(coroutineContext.job === outer.job)

    withContext(Dispatchers.Default) {
        println(coroutineContext === outer)
        println(coroutineContext[CoroutineName]?.name)
        println(coroutineContext.job === outer.job)
    }

    withContext(CoroutineName("inner") + Dispatchers.Default) {
        println(coroutineContext[CoroutineName]?.name)
        println(coroutineContext.job === outer.job)
    }

    // Empty override short-circuits on the JVM: no child context at all.
    withContext(EmptyCoroutineContext) {
        println(coroutineContext === outer)
        println(coroutineContext.job === outer.job)
    }
    println("done")
}
