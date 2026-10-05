import kotlinx.coroutines.*

suspend fun throughCoroutine(block: suspend CoroutineScope.() -> Int): Any =
    coroutineScope(block = block)

suspend fun throughSupervisor(block: suspend CoroutineScope.() -> Int): Any =
    supervisorScope(block)

fun main() = runBlocking {
    val block: suspend CoroutineScope.() -> Int = { 23 }
    println(coroutineScope(block = block))
    println(supervisorScope(block = block))
    val nullable: suspend CoroutineScope.() -> Int? = { null }
    println(coroutineScope(block = nullable))
    println(supervisorScope(block = nullable))

    val label = "captured"
    val increment = 4
    val offset = 19
    var state = 3
    val captured: suspend CoroutineScope.() -> Int = {
        delay(1)
        println(label)
        this.ensureActive()
        println(this.coroutineContext.job === currentCoroutineContext().job)
        state += increment
        state + offset
    }
    println(throughCoroutine(captured))
    println(throughSupervisor(captured))
    println(state)

    println(coroutineScope {
        val scope: CoroutineScope = this
        scope.async { delay(1); 7 }.await()
    })
    println(supervisorScope {
        val scope: CoroutineScope = this
        scope.async { delay(1); 11 }.await()
    })

    val throwing: suspend CoroutineScope.() -> Int = {
        delay(1)
        throw IllegalArgumentException(label)
    }
    try {
        throughCoroutine(throwing)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        throughSupervisor(throwing)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    Unit
}
