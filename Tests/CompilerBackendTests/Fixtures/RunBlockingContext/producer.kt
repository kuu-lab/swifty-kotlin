package runblocking1765.producer
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.*

public fun <T> invokeInContext(context: CoroutineContext, block: suspend CoroutineScope.() -> T): T =
    runBlocking(block = block, context = context)

public fun storedAndJoined(prefix: String, suffix: String): String {
    var joined = false
    val block: suspend CoroutineScope.() -> String = {
        launch { delay(1); joined = true }
        delay(1)
        prefix + ":" + currentCoroutineContext()[CoroutineName]?.name + ":" + suffix
    }
    val value = runBlocking(context = CoroutineName("producer"), block = block)
    check(joined)
    return value
}
