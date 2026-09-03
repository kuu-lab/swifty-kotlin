import kotlinx.coroutines.runBlocking

suspend fun sourceSuspend(): String = "ok"

fun makeSuspendFunction(): suspend () -> String =
    suspend { sourceSuspend() }

fun main() {
    runBlocking {
        println((suspend { sourceSuspend() })())
    }
}
