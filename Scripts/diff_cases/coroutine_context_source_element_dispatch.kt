import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

object Key : CoroutineContext.Key<CustomElement>
object OtherKey : CoroutineContext.Key<CustomElement>

open class CustomElement : CoroutineContext.Element {
    override val key: CoroutineContext.Key<*> = Key
}

class Derived : CustomElement()

class ThrowingElement : CustomElement() {
    override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? {
        throw IllegalStateException("get")
    }

    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext {
        throw IllegalArgumentException("minusKey")
    }
}

fun <T : CoroutineContext> probe(context: T, element: CustomElement) {
    val indexed: CustomElement? = context[Key]
    val explicit: CustomElement? = context.get(Key)
    println(indexed === element)
    println(explicit === element)
    println(context[OtherKey] == null)
    println(context.minusKey(Key) === EmptyCoroutineContext)
    println(context.minusKey(OtherKey) === element)
}

fun main() {
    val element = CustomElement()
    val context: CoroutineContext = element
    probe(context, element)
    val derived = Derived()
    probe(derived, derived)
    val throwing: CoroutineContext = ThrowingElement()
    try { throwing[Key] } catch (e: IllegalStateException) { println(e.message) }
    try { throwing.get(Key) } catch (e: IllegalStateException) { println(e.message) }
    try { throwing.minusKey(Key) } catch (e: IllegalArgumentException) { println(e.message) }
}
