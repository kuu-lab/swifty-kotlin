import kotlinx.coroutines.*

fun main() {
    runBlocking {
        val captured = 7
        val first = async(start = CoroutineStart.LAZY) {
            println("await-driven lazy: $captured")
            captured
        }
        println(first.await())

        val second = async(start = CoroutineStart.LAZY) {
            println("start-driven lazy: $captured")
            captured + 10
        }
        second.start()
        println(second.await())

        val third = async {
            println("default after resume: $captured")
            captured
        }
        println(third.await())

        val atomic = async(start = CoroutineStart.ATOMIC) {
            println("atomic after cancel: $captured")
            captured
        }
        atomic.cancel()
        atomic.join()
    }
}
