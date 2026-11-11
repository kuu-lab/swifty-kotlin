import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.AbstractCoroutineContextKey
import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

private object FirstKey : CoroutineContext.Key<First>
private object SecondKey : CoroutineContext.Key<Second>
private class First(val label: String) : CoroutineContext.Element {
    override val key: CoroutineContext.Key<*> get() = FirstKey
    override fun toString(): String = label
}
private class Second : AbstractCoroutineContextElement(SecondKey) {
    override fun toString(): String = "second"
}
private object DispatcherKey : AbstractCoroutineContextKey<ContinuationInterceptor, Dispatcher>(
    ContinuationInterceptor.Key, { it as? Dispatcher }
)
private class Dispatcher : AbstractCoroutineContextElement(ContinuationInterceptor.Key), ContinuationInterceptor {
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> = continuation
    override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? = super<ContinuationInterceptor>.get(key)
    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext = super<ContinuationInterceptor>.minusKey(key)
    override fun toString(): String = "dispatcher"
}

fun main() {
    val first = First("first")
    val replacement = First("replacement")
    val second = Second()
    val dispatcher = Dispatcher()
    val combined = first + dispatcher + second
    check(combined[FirstKey] === first)
    check(combined[ContinuationInterceptor.Key] === dispatcher)
    check(combined[DispatcherKey] === dispatcher)
    check((combined + replacement)[FirstKey] === replacement)
    check(combined.minusKey(DispatcherKey)[ContinuationInterceptor.Key] == null)
    check(combined == second + dispatcher + first)
    check(combined.hashCode() == (second + dispatcher + first).hashCode())
    check((first + EmptyCoroutineContext) === first)
    check(EmptyCoroutineContext.plus(first) === first)
    println(combined.fold("") { text, element -> text + element.toString() + " " }.trim())
}
