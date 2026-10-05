import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

object Key : CoroutineContext.Key<Element>
object OtherKey : CoroutineContext.Key<Element>

object Element : CoroutineContext.Element {
    override val key: CoroutineContext.Key<*> = Key
}

interface MutableValue {
    var value: Int
}

object Value : MutableValue {
    override var value: Int = 7
}

fun <T : CoroutineContext> probe(context: T) {
    println(context.get(Key) === Element)
    println(context[Key] === Element)
    println(context.get(OtherKey) == null)
    println(context.minusKey(Key) === EmptyCoroutineContext)
    println(context.minusKey(OtherKey) === Element)
}

fun main() {
    val context: CoroutineContext = Element
    println(context.get(Key) === Element)
    println(context.minusKey(Key) === EmptyCoroutineContext)
    probe(context)
    val nullable: CoroutineContext? = Element
    println(nullable?.get(Key) === Element)
    println(nullable?.minusKey(Key) === EmptyCoroutineContext)
    println(Element.key === Key)
    val value: MutableValue = Value
    println(value.value)
    value.value = 9
    println(Value.value)
    Value.value = 11
    println(value.value)
}
