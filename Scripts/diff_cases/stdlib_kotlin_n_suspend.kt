import kotlinx.coroutines.runBlocking

private suspend fun sourceSuspend(): String = "ok"

fun main() = runBlocking {
    val block = suspend { sourceSuspend() }
    println(block())
}
