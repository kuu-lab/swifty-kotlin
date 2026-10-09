import kotlin.coroutines.*

class StoredCompletion(override val context: CoroutineContext) : Continuation<Int> {
    override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
}

class GetterCompletion : Continuation<Int> {
    override val context: CoroutineContext
        get() {
            println("getter")
            return EmptyCoroutineContext
        }
    override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
}

fun readContext(completion: Continuation<Int>) {
    println(completion.context === EmptyCoroutineContext)
}

fun main() {
    readContext(StoredCompletion(EmptyCoroutineContext))
    readContext(GetterCompletion())
    readContext(object : Continuation<Int> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
    })
    val native = Continuation<Int>(EmptyCoroutineContext) { result -> println(result.getOrThrow()) }
    readContext(native)
    native.resume(7)
    val block: suspend () -> Int = { 42 }
    block.startCoroutine(StoredCompletion(EmptyCoroutineContext))
}
