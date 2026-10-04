@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.coroutines.AbstractCoroutineContextKey
import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

open class IdentityInterceptor : ContinuationInterceptor {
    override val key: CoroutineContext.Key<*> = ContinuationInterceptor.Key
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> = continuation
}

class SpecialInterceptor : IdentityInterceptor()

object SpecialKey : AbstractCoroutineContextKey<ContinuationInterceptor, SpecialInterceptor>(
    ContinuationInterceptor.Key, { element -> element as? SpecialInterceptor }
)

object ChainedKey : AbstractCoroutineContextKey<SpecialInterceptor, SpecialInterceptor>(
    SpecialKey, { element -> element as? SpecialInterceptor }
)

object UnrelatedKey : CoroutineContext.Key<ContinuationInterceptor>

object UnrelatedPolymorphicKey : AbstractCoroutineContextKey<ContinuationInterceptor, SpecialInterceptor>(
    UnrelatedKey, { element -> element as? SpecialInterceptor }
)

class RecordingInterceptor : IdentityInterceptor() {
    var released: Int = 0
    override fun releaseInterceptedContinuation(continuation: Continuation<*>) {
        released += 1
    }
}

class Completion : Continuation<String> {
    override val context: CoroutineContext = EmptyCoroutineContext
    override fun resumeWith(result: Result<String>) { println(result.getOrThrow()) }
}

fun main() {
    println(ContinuationInterceptor === ContinuationInterceptor.Key)
    println((ContinuationInterceptor.Key as Any) is CoroutineContext.Key<*>)
    val interceptor: ContinuationInterceptor = SpecialInterceptor()
    println(interceptor[ContinuationInterceptor.Key] === interceptor)
    println(interceptor[SpecialKey] === interceptor)
    println(interceptor[ChainedKey] === interceptor)
    println(interceptor[UnrelatedKey] == null)
    println(interceptor[UnrelatedPolymorphicKey] == null)
    println(interceptor.minusKey(ContinuationInterceptor.Key) === EmptyCoroutineContext)
    println(interceptor.minusKey(SpecialKey) === EmptyCoroutineContext)
    println(interceptor.minusKey(ChainedKey) === EmptyCoroutineContext)
    println(interceptor.minusKey(UnrelatedKey) === interceptor)
    println(interceptor.minusKey(UnrelatedPolymorphicKey) === interceptor)
    val plain: ContinuationInterceptor = IdentityInterceptor()
    println(plain[SpecialKey] == null)
    println(plain.minusKey(SpecialKey) === plain)
    val completion = Completion()
    val intercepted = interceptor.interceptContinuation(completion)
    println(intercepted === completion)
    intercepted.resumeWith(Result.success("resumed"))
    interceptor.releaseInterceptedContinuation(intercepted)
    println("default released")
    val recording: ContinuationInterceptor = RecordingInterceptor()
    recording.releaseInterceptedContinuation(completion)
    println((recording as RecordingInterceptor).released)
}
