// KUU-1676: the obsolete ticker API remains available and its channel stops
// producing when cancelled.
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.*

@OptIn(ObsoleteCoroutinesApi::class)
fun main() = runBlocking {
    val t = ticker(10, 0)
    t.receive()
    t.cancel()
    println("ticker-ok")
}
