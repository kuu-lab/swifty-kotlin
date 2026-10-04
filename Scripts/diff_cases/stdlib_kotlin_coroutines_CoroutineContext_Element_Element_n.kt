import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

private class Marker : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<Marker>
    override val key: CoroutineContext.Key<*> get() = Key
}

private class Other : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<Other>
    override val key: CoroutineContext.Key<*> get() = Key
}

fun main() {
    val element: CoroutineContext.Element = Marker()
    println(element.key === Marker.Key)
    println(element[Marker.Key] === element)
    println(element[Other.Key] == null)
    println(element.fold(5) { value, current -> if (current === element) value + 1 else value })
    println(element.minusKey(Marker.Key) === EmptyCoroutineContext)
    println(element.minusKey(Other.Key) === element)
}
