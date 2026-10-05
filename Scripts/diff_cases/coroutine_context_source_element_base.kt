import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

object Key : CoroutineContext.Key<Element>
object OtherKey : CoroutineContext.Key<Element>
class Element : CoroutineContext.Element {
    override val key: CoroutineContext.Key<*> = Key
}

fun main() {
    val element = Element()
    val context: CoroutineContext = element
    println(context[Key] === element)
    println(context.get(Key) === element)
    println(context[OtherKey] == null)
    println(context.minusKey(Key) === EmptyCoroutineContext)
    println(context.minusKey(OtherKey) === element)
    println(context.fold(5) { value, current -> if (current === element) value + 1 else value })
}
