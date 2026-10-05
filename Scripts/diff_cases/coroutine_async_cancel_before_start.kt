import kotlinx.coroutines.*

@OptIn(ExperimentalCoroutinesApi::class)
fun main() {
    runBlocking {
        val task = async { println("cancelled body"); 1 }
        task.cancel()
        yield()
        task.join()
        println("joined")
        try {
            task.await()
        } catch (e: CancellationException) {
            println("await cancelled")
        }

        val captured = 7
        val capturing = async { println("cancelled capture $captured"); captured }
        capturing.cancel()
        capturing.join()
        println("capture joined")

        val lazy = async(start = CoroutineStart.LAZY) { println("cancelled lazy"); 2 }
        lazy.cancel(null)
        lazy.join()
        println("lazy joined")
        val lazyCapturing = async(start = CoroutineStart.LAZY) { println("cancelled lazy capture $captured"); captured }
        lazyCapturing.cancel()
        lazyCapturing.join()
        println("lazy capture joined")

        val atomic = async(start = CoroutineStart.ATOMIC) {
            println("atomic body")
            try {
                yield()
                println("atomic after yield")
            } finally {
                println("atomic finally")
            }
            3
        }
        atomic.cancel()
        atomic.join()
        println("atomic joined")
        val atomicCapturing = async(start = CoroutineStart.ATOMIC) { println("atomic capture $captured"); captured }
        atomicCapturing.cancel()
        atomicCapturing.join()
        println("atomic capture joined")

        val running = async {
            try {
                println("running body")
                yield()
            } finally {
                println("running finally")
            }
            4
        }
        yield()
        running.cancel()
        running.join()
        println("running joined")

        val completed = async { 5 }
        completed.join()
        println("completed value ${completed.await()}")

        supervisorScope {
            val failed = async { throw IllegalStateException("failure") }
            failed.join()
            println("failed joined")
            try {
                failed.await()
            } catch (e: IllegalStateException) {
                println("await failure ${e.message}")
            }
            val failedFinally = async(start = CoroutineStart.ATOMIC) {
                try {
                    yield()
                } finally {
                    throw IllegalStateException("finally failure")
                }
            }
            failedFinally.cancel()
            failedFinally.join()
            println("failed finally joined")
            try {
                failedFinally.await()
            } catch (e: IllegalStateException) {
                println("await finally failure ${e.message}")
            }
        }
    }
}
