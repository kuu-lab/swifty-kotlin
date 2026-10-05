import kotlinx.coroutines.*

private suspend fun invokeBlock(block: suspend () -> Int): Int = block()

fun main() = runBlocking {
    val block = suspend { delay(10); 42 }
    println(block())
    println(invokeBlock(block))
    val immediate = suspend { 43 }
    println(invokeBlock(immediate))
    val seed = 41
    val captured = suspend { delay(10); seed + 1 }
    println(captured())
    println(invokeBlock(captured))
}
