import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.startCoroutine

private val completion = object : Continuation<Unit> {
    override val context: kotlin.coroutines.CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<Unit>) { result.getOrThrow() }
}

private fun builder(block: suspend String.() -> Unit) {
    block.startCoroutine("OK", completion)
}

private fun <T> genericBuilder(value: T, block: suspend T.() -> Unit) {
    block.startCoroutine(value, completion)
}

interface A {
    var result: String

    fun test(): String {
        builder { result = this }
        return result
    }
}

interface GenericA<T> {
    var result: T

    fun test(value: T): T {
        genericBuilder(value) { result = this }
        return result
    }
}

fun main() {
    println(object : A { override var result = "Fail" }.test())
    println(object : GenericA<String> { override var result = "Fail" }.test("Generic OK"))
}
