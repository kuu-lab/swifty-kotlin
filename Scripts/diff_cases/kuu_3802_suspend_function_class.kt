import kotlin.coroutines.Continuation
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.resume
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.createCoroutineUnintercepted
import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlin.coroutines.startCoroutine

// KUU-3802: a named class implementing a suspend function type is an ordinary
// object — it must still behave like a suspend function value through the
// coroutine builder APIs and direct suspend invocation.

class NonSuspendingFunction : suspend () -> String {
    override suspend fun invoke(): String = "OK"
}

class Greeter : suspend (String) -> String {
    override suspend fun invoke(name: String): String = "hi:$name"
}

class Adder : suspend (Int, Int) -> Int {
    override suspend fun invoke(a: Int, b: Int): Int = a + b
}

class SuspendingFunction : suspend () -> String {
    override suspend fun invoke(): String {
        val value = suspendCoroutineUninterceptedOrReturn<String> { cont ->
            cont.resume("S")
            COROUTINE_SUSPENDED
        }
        return "resumed:$value"
    }
}

suspend fun callIt(f: suspend () -> String): String = f()
suspend fun greetIt(g: suspend (String) -> String): String = g("zed")
suspend fun sumIt(a: suspend (Int, Int) -> Int): Int = a(3, 4)

fun main() {
    val f: suspend () -> String = NonSuspendingFunction()

    var result: Result<String>? = null
    f.startCoroutine(Continuation(EmptyCoroutineContext) { result = it })
    println(result?.getOrNull())

    val g: suspend (String) -> String = Greeter()
    var greeted: Result<String>? = null
    g.startCoroutine("bob", Continuation(EmptyCoroutineContext) { greeted = it })
    println(greeted?.getOrNull())

    println(f.startCoroutineUninterceptedOrReturn(Continuation(EmptyCoroutineContext) { }))
    println(g.startCoroutineUninterceptedOrReturn("amy", Continuation(EmptyCoroutineContext) { }))

    var lazyResult: Result<String>? = null
    val pending = f.createCoroutineUnintercepted(Continuation(EmptyCoroutineContext) { lazyResult = it })
    println(lazyResult?.getOrNull())
    pending.resume(Unit)
    println(lazyResult?.getOrNull())

    var nested: Result<String>? = null
    val caller: suspend () -> String = { callIt(NonSuspendingFunction()) }
    caller.startCoroutine(Continuation(EmptyCoroutineContext) { nested = it })
    println(nested?.getOrNull())

    var greetedDirect: Result<String>? = null
    val greetCaller: suspend () -> String = { greetIt(Greeter()) }
    greetCaller.startCoroutine(Continuation(EmptyCoroutineContext) { greetedDirect = it })
    println(greetedDirect?.getOrNull())

    var summed: Result<Int>? = null
    val sumCaller: suspend () -> Int = { sumIt(Adder()) }
    sumCaller.startCoroutine(Continuation(EmptyCoroutineContext) { summed = it })
    println(summed?.getOrNull())

    var suspended: Result<String>? = null
    val s: suspend () -> String = SuspendingFunction()
    s.startCoroutine(Continuation(EmptyCoroutineContext) { suspended = it })
    println(suspended?.getOrNull())
}
