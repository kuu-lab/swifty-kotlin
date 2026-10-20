import kotlin.coroutines.*
class Gate {
    var pending: Continuation<Int>? = null
    suspend fun await(): Int = suspendCoroutine { pending = it }
    fun release(value: Int) { pending!!.resume(value) }
    fun reject() { pending!!.resumeWithException(IllegalStateException("failed")) }
}
class Sink : Continuation<Int> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
}
class FailureSink : Continuation<Int> {
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: Result<Int>) {
        println(result.isSuccess)
        println(result.isFailure)
        println(result.exceptionOrNull()!!.message)
    }
}
fun main() {
    val gate = Gate()
    val work: suspend () -> Int = {
        var sum = 0L
        var index = 0
        while (index < 2) { sum += gate.await(); index++ }
        try { gate.await() } catch (failure: IllegalStateException) {
            println(failure.message)
        } finally { println("finally") }
        sum.toInt()
    }
    work.startCoroutine(Sink())
    println("paused")
    gate.release(20)
    println("paused again")
    gate.release(22)
    println("awaiting failure")
    gate.reject()
    val fail: suspend () -> Int = { gate.await() }
    fail.startCoroutine(FailureSink())
    gate.reject()
}
