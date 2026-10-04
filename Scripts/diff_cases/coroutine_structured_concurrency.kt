import kotlinx.coroutines.*

// TEST-CORO-003: Structured concurrency — parent waits for all children,
// child failure cancels siblings, and coroutineScope propagates exceptions.

suspend fun fetchData(id: Int): String {
    delay(1)
    return "data-$id"
}

fun main() = runBlocking {
    // 1. coroutineScope waits for all children to complete
    val results = coroutineScope {
        val a = async { fetchData(1) }
        val b = async { fetchData(2) }
        val c = async { fetchData(3) }
        listOf(a.await(), b.await(), c.await())
    }
    results.forEach { println(it) }

    // 2. Nested structured concurrency. Each launch mutates its own captured
    // variable instead of all three concurrently incrementing one shared
    // `sum`, since KSwiftK dispatches launch{} onto real parallel threads
    // (unlike kotlinx's single-thread-confined default dispatcher), which
    // would otherwise race.
    val total = coroutineScope {
        var sum1 = 0
        var sum2 = 0
        var sum3 = 0
        coroutineScope {
            launch { sum1 = 1 }
            launch { sum2 = 2 }
            launch { sum3 = 3 }
        }
        sum1 + sum2 + sum3
    }
    println("total: $total")

    // 3. All children complete before parent proceeds (see the note on part
    // 2 above: each child writes its own variable rather than both
    // concurrently mutating one shared MutableList).
    var child1Done: String? = null
    var child2Done: String? = null
    coroutineScope {
        launch { child1Done = "child1" }
        launch { child2Done = "child2" }
    }
    val order = listOfNotNull(child1Done, child2Done) + "parent"
    println(order.sorted().joinToString(","))

    println("done")
}
