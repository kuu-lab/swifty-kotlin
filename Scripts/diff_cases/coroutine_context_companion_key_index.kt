import kotlin.coroutines.*
import kotlinx.coroutines.*

object OtherKey : CoroutineContext.Key<Item>

class Item(val value: Int) : AbstractCoroutineContextElement(Item.Key) {
    companion object Key : CoroutineContext.Key<Item>
}

interface Token<T>

class Value {
    companion object Named : Token<Value>
}

class Lookup {
    operator fun <T> get(key: Token<T>): T? = null
}

fun probe(context: CoroutineContext, key: CoroutineContext.Key<Item>) {
    val job: Job? = context[Job]
    val explicitJob: Job? = context[Job.Key]
    val item: Item? = context[Item]
    val explicitItem: Item? = context[Item.Key]
    val parameterKey: Item? = context[key]
    println("context-index-ok")
}

fun main() = runBlocking {
    probe(coroutineContext, Item.Key)
    probe(EmptyCoroutineContext, Item.Key)
    probe(EmptyCoroutineContext + Job(), Item.Key)
    println(EmptyCoroutineContext[Job] == null)
    println(EmptyCoroutineContext[Item] == null)
    println(Item(42)[Item]?.value)
    println(Item(42)[Item.Key]?.value)
    println(Item(42)[OtherKey] == null)
    println(Lookup()[Value] == null)
}
