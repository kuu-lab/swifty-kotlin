import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

object Key : CoroutineContext.Key<Item>
class Item : CoroutineContext.Element {
    override val key: CoroutineContext.Key<*> get() = Key
}

open class CustomContext(val item: Item) : CoroutineContext {
    @Suppress("UNCHECKED_CAST")
    override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? = item as E
    override fun <R> fold(initial: R, operation: (R, CoroutineContext.Element) -> R): R =
        operation(operation(initial, item), item)
    override fun plus(context: CoroutineContext): CoroutineContext = this
    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext = this
}

class ThrowingContext(item: Item) : CustomContext(item) {
    override fun plus(context: CoroutineContext): CoroutineContext {
        throw IllegalArgumentException("plus override")
    }
}

fun main() {
    val item = Item()
    val empty: CoroutineContext = EmptyCoroutineContext
    println(empty.fold(0) { acc, _ -> acc + 1 })
    println(empty[Key] == null)
    println(empty.minusKey(Key) === empty)
    println(empty.plus(item) === item)
    println((empty + item) === item)

    val element: CoroutineContext = item
    val step = 3
    println(element.fold(10) { acc, e -> if (e === item) acc + step else -1 })
    println(element[Key] === item)
    println(element.minusKey(Key) === EmptyCoroutineContext)
    // Inherited plus entries must not recursively dispatch back into the bridge.
    element.plus(empty)
    element + empty
    println("inherited plus")

    val custom: CoroutineContext = CustomContext(item)
    println(custom.fold(10) { acc, e -> if (e === item) acc + step else -1 })
    println(custom[Key] === item)
    println(custom.minusKey(Key) === custom)
    println(custom.plus(empty) === custom)
    println((custom + empty) === custom)
    println(custom.fold("start") { acc, _ -> acc + ":item" })
    try {
        custom.fold(0) { _, _ -> throw IllegalStateException("fold override") }
    } catch (e: IllegalStateException) {
        println(e.message)
    }
    val throwing: CoroutineContext = ThrowingContext(item)
    try {
        throwing.plus(empty)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    try {
        throwing + empty
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    var mutable: CoroutineContext = throwing
    try {
        mutable += empty
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
    println(mutable === throwing)
}
