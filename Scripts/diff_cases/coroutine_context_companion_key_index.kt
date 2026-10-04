import kotlin.coroutines.*
import kotlinx.coroutines.*

object ItemKey : CoroutineContext.Key<Item>

class Item(val value: Int) : AbstractCoroutineContextElement(ItemKey) {
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
    probe(coroutineContext, ItemKey)
    probe(EmptyCoroutineContext, ItemKey)
    println(EmptyCoroutineContext[Job] == null)
    println(EmptyCoroutineContext[Item] == null)
    println(Item(42)[ItemKey]?.value)
    println(Item(42)[Item] == null)
    println(Lookup()[Value] == null)
}
