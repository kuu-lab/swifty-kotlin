import kotlin.coroutines.*
import kotlin.coroutines.intrinsics.*

// KUU-3832: a suspend function's completion value must reach the
// `Result` delivered to the completion continuation in boxed form
// (`Result.success(v)` semantics). Raw ABI values surfaced as
// `Success(0)` for Unit, `Success(1)` for true, IEEE-754 bits for
// Double/Float, ordinals for enums, and code points for Char.

var cont: Continuation<Int>? = null

suspend fun sInt(): Int = suspendCoroutineUninterceptedOrReturn { x ->
    cont = x
    COROUTINE_SUSPENDED
}

suspend fun testUnitSuspend(): Unit { sInt() }
suspend fun testUnitImmediate(): Unit { }
suspend fun testBool(): Boolean { sInt(); return true }
suspend fun testChar(): Char { sInt(); return 'a' }
suspend fun testDouble(): Double { sInt(); return 1.5 }
suspend fun testEnum(): Color { sInt(); return Color.GREEN }
suspend fun testInt(): Int { return sInt() }

enum class Color { RED, GREEN }

fun main() {
    ::testUnitImmediate.startCoroutine(Continuation(EmptyCoroutineContext) { println("unitImmediate: $it") })
    ::testUnitSuspend.startCoroutine(Continuation(EmptyCoroutineContext) { println("unitSuspend: $it") })
    cont!!.resume(42)
    ::testBool.startCoroutine(Continuation(EmptyCoroutineContext) { println("bool: $it") })
    cont!!.resume(43)
    ::testChar.startCoroutine(Continuation(EmptyCoroutineContext) { println("char: $it") })
    cont!!.resume(44)
    ::testDouble.startCoroutine(Continuation(EmptyCoroutineContext) { println("double: $it") })
    cont!!.resume(45)
    ::testEnum.startCoroutine(Continuation(EmptyCoroutineContext) { println("enum: $it") })
    cont!!.resume(46)
    ::testInt.startCoroutine(Continuation(EmptyCoroutineContext) { println("int: $it") })
    cont!!.resume(47)
}
