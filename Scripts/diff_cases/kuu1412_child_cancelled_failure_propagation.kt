// JobSupport.childCancelled with a non-cancellation cause cancels its parent.
@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

import kotlinx.coroutines.*
import kotlinx.coroutines.internal.*

@OptIn(InternalCoroutinesApi::class)
fun main() {
    try {
        runBlocking {
            val child: Job = launch { delay(5000) }
            println("before childCancelled")
            val handled = (child as JobSupport).childCancelled(RuntimeException("child failure"))
            println(
                "after childCancelled handled=$handled childActive=${child.isActive} " +
                    "parentActive=${coroutineContext.job.isActive}"
            )
        }
    } catch (e: RuntimeException) {
        println("caught=${e.message}")
    }
}
