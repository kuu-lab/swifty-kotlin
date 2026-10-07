// KUU-1387: `coroutineContext` must be referentially stable. On the JVM the
// ambient context is a per-coroutine singleton, so repeated reads return the
// same instance (`===` and `==` both true). The runtime used to allocate a
// fresh wrapper per access, making even `coroutineContext === coroutineContext`
// false.
import kotlinx.coroutines.*
import kotlin.coroutines.*

suspend fun probe(caller: CoroutineContext) {
    val a = coroutineContext
    delay(1)
    val b = coroutineContext
    println("probe: a===b ${a === b} a===caller ${a === caller} jobstable ${coroutineContext.job === caller.job}")
}

fun main() = runBlocking {
    println(coroutineContext == coroutineContext)
    println(coroutineContext === coroutineContext)
    println(coroutineContext.job === coroutineContext.job)
    println(currentCoroutineContext() == coroutineContext)
    println(currentCoroutineContext() === coroutineContext)

    val outer = coroutineContext
    probe(outer)

    val d = async { coroutineContext }
    val dc = d.await()
    println("async: distinct ${dc !== outer} selfStable ${dc === d.await()}")

    suspendCoroutine<Unit> { cont ->
        println("suspendCoroutine: cont.context===outer ${cont.context === outer} jobmatch ${cont.context.job === outer.job}")
        cont.resumeWith(Result.success(Unit))
    }
    println("afterSC: ${coroutineContext === outer}")

    val j = launch { println("launch: self ${coroutineContext === coroutineContext}") }
    j.join()
    println("end: ${coroutineContext === outer}")
}
