import kotlinx.coroutines.*

fun runValue(block: suspend CoroutineScope.() -> Int): Int = runBlocking(block = block)
fun forwardValue(block: suspend CoroutineScope.() -> Int): Int = runValue(block)
fun forwardAgain(block: suspend CoroutineScope.() -> Int): Int = forwardValue(block)
fun runText(block: suspend CoroutineScope.() -> String): String = runBlocking(block = block)

fun CoroutineScope.scopeValue(): Int = 9

fun launchValue(scope: CoroutineScope, block: suspend CoroutineScope.() -> Unit): Job =
    scope.launch(block = block)

fun asyncValue(block: suspend CoroutineScope.() -> Int): Int =
    runBlocking { async(block = block).await() }

fun main() {
    val bonus = 7
    val block: suspend CoroutineScope.() -> Int = { bonus + 23 }
    println(runValue(block))
    println(forwardAgain(block))
    println(runValue { bonus + 23 })

    val extra = 23
    val multiple: suspend CoroutineScope.() -> Int = {
        delay(1)
        scopeValue() + bonus + extra
    }
    println(forwardAgain(multiple))

    var counter = 1
    val mutable: suspend CoroutineScope.() -> Int = {
        delay(1)
        counter += bonus
        counter
    }
    println(runValue(mutable))
    println(forwardAgain(mutable))
    println(counter)

    val zero: suspend CoroutineScope.() -> Int = { scopeValue() }
    println(forwardAgain(zero))
    val label = "captured"
    val text: suspend CoroutineScope.() -> String = {
        delay(1)
        label
    }
    println(runText(text))
    println(asyncValue(multiple))

    runBlocking {
        val scope: CoroutineScope = this
        val update: suspend CoroutineScope.() -> Unit = {
            delay(1)
            counter += scopeValue() + bonus
        }
        launchValue(scope, update).join()
        println(counter)
    }
}
