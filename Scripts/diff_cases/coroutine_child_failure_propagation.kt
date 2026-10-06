import kotlinx.coroutines.*

fun main() {
    try {
        runBlocking {
            val sibling = launch { delay(5000); println("async sibling survived") }
            val failed = async { delay(1); throw IllegalStateException("async kill") }
            try { failed.await() } catch (e: IllegalStateException) { println("await threw") }
            println("async sibling active: ${sibling.isActive}")
            println("async scope active: ${coroutineContext.job.isActive}")
        }
    } catch (e: IllegalStateException) { println(e.message) }

    try {
        runBlocking {
            launch { delay(5000); println("launch sibling survived") }
            launch { delay(1); throw IllegalStateException("launch kill") }
            try { delay(5000) } catch (e: CancellationException) { println("parent cancelled") }
            println("launch scope active: ${coroutineContext.job.isActive}")
        }
    } catch (e: IllegalStateException) { println(e.message) }

    try {
        runBlocking {
            launch { delay(5000); println("joining sibling survived") }
            async { delay(1); throw IllegalStateException("joining kill") }
        }
    } catch (e: IllegalStateException) { println(e.message) }

    try {
        runBlocking {
            launch {
                try { delay(5000) } finally { throw IllegalArgumentException("later cleanup") }
            }
            async { delay(1); throw IllegalStateException("first while joining") }
        }
    } catch (e: IllegalStateException) { println(e.message) }

    runBlocking {
        supervisorScope {
            val sibling = launch { delay(10); println("supervisor sibling completed") }
            val failed = async { delay(1); throw IllegalStateException("supervisor kill") }
            try { failed.await() } catch (e: IllegalStateException) { println(e.message) }
            println("supervisor scope active: ${coroutineContext.job.isActive}")
            sibling.join()
        }
        try {
            coroutineScope {
                launch { delay(5000); println("nested sibling survived") }
                async { delay(1); throw IllegalStateException("nested kill") }
                delay(5000)
            }
        } catch (e: IllegalStateException) { println(e.message) }
        println("outer scope active: ${coroutineContext.job.isActive}")
        try {
            coroutineScope {
                async { delay(1); throw IllegalStateException("first child failure") }
                try { delay(5000) } catch (e: CancellationException) {
                    throw IllegalArgumentException("second body failure")
                }
            }
        } catch (e: IllegalStateException) { println(e.message) }
        try {
            coroutineScope {
                launch {
                    try { delay(5000) } finally { throw IllegalStateException("cleanup failure") }
                }
                delay(1)
                cancel()
            }
        } catch (e: IllegalStateException) { println(e.message) }
    }
}
