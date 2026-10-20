package kotlin.coroutines.intrinsics
private object CoroutineSuspended
val COROUTINE_SUSPENDED: Any get() = CoroutineSuspended
fun <T> intercepted(continuation: kotlin.coroutines.Continuation<T>): kotlin.coroutines.Continuation<T> = continuation
