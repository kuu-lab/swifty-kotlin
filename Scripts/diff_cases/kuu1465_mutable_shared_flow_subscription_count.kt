import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.StateFlow

fun main() = runBlocking {
    val shared = MutableSharedFlow<Int>(replay = 1)
    shared.tryEmit(41)
    val count: StateFlow<Int> = shared.subscriptionCount

    val subscription = launch { shared.collect {} }
    delay(5)
    println(count.value)

    subscription.cancelAndJoin()
    println(count.value)
}
