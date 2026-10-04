@file:OptIn(ExperimentalCoroutinesApi::class)

import kotlinx.coroutines.*

fun main() = runBlocking {
    val root = coroutineContext.job
    val first = launch(start = CoroutineStart.LAZY) {}
    val second = launch(start = CoroutineStart.LAZY) {}
    println(root.children.toList().size)
    println(first.parent === root)
    println(second.parent === root)
    first.join()
    println(first.parent == null)
    println(root.children.toList().size)
    var cancelled = false
    second.invokeOnCompletion { cause -> cancelled = cause != null }
    root.cancelChildren(CancellationException("siblings"))
    second.join()
    println(cancelled)
    println(second.isCancelled)
    println(root.isActive)
    println(root.children.toList().size)
    val third = launch(start = CoroutineStart.LAZY) {}
    root.cancelChildren()
    third.join()
    println(third.isCancelled)
    println(root.isActive)
}
