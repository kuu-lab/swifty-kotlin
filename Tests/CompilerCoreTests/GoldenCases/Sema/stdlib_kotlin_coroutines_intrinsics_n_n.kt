package golden.sema

import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
import kotlin.coroutines.Continuation
import kotlin.coroutines.intrinsics.intercepted

suspend fun probe(): Any? =
    suspendCoroutineUninterceptedOrReturn { COROUTINE_SUSPENDED }

fun main() {
    println(COROUTINE_SUSPENDED === COROUTINE_SUSPENDED)
}

fun <T> intercept(continuation: Continuation<T>): Continuation<T> = continuation.intercepted()
