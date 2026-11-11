package kotlin.coroutines

interface CoroutineContext {
    operator fun <E : Element> get(key: Key<E>): E?
    fun <R> fold(initial: R, operation: (R, Element) -> R): R
    fun minusKey(key: Key<*>): CoroutineContext

    operator fun plus(context: CoroutineContext): CoroutineContext =
        context.fold<CoroutineContext>(this, ::appendContextElement)

    interface Key<E : Element>

    interface Element : CoroutineContext {
        val key: Key<*>

        @Suppress("UNCHECKED_CAST")
        override operator fun <E : Element> get(key: Key<E>): E? =
            if (this.key == key) this as E else null

        override fun <R> fold(initial: R, operation: (R, Element) -> R): R =
            operation(initial, this)

        override fun minusKey(key: Key<*>): CoroutineContext =
            if (this.key == key) EmptyCoroutineContext else this
    }
}

private fun appendContextElement(context: CoroutineContext, element: CoroutineContext.Element): CoroutineContext {
    val remaining = context.minusKey(element.key)
    if (remaining === EmptyCoroutineContext) return element
    val interceptor = remaining[ContinuationInterceptor.Key]
    if (interceptor == null) return CombinedContext(remaining, element)
    // Keeping the interceptor last makes dispatcher lookup independent of context size.
    val withoutInterceptor = remaining.minusKey(ContinuationInterceptor.Key)
    if (withoutInterceptor === EmptyCoroutineContext) return CombinedContext(element, interceptor)
    return CombinedContext(CombinedContext(withoutInterceptor, element), interceptor)
}

object EmptyCoroutineContext : CoroutineContext, java.io.Serializable {
    override operator fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? = null
    override fun <R> fold(initial: R, operation: (R, CoroutineContext.Element) -> R): R = initial
    override fun plus(context: CoroutineContext): CoroutineContext = context
    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext = this
    override fun hashCode(): Int = 0
    override fun toString(): String = "EmptyCoroutineContext"

    private fun readResolve(): Any = EmptyCoroutineContext
}

abstract class AbstractCoroutineContextElement(override val key: CoroutineContext.Key<*>) : CoroutineContext.Element

internal class CombinedContext(
    private val left: CoroutineContext,
    private val element: CoroutineContext.Element
) : CoroutineContext, java.io.Serializable {
    override operator fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? {
        var current = this
        while (true) {
            val value = current.element[key]
            if (value != null) return value
            val next = current.left
            if (next !is CombinedContext) return next[key]
            current = next
        }
    }

    override fun <R> fold(initial: R, operation: (R, CoroutineContext.Element) -> R): R =
        operation(left.fold<R>(initial, operation), element)

    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext {
        if (element[key] != null) return left
        val remaining = left.minusKey(key)
        if (remaining === left) return this
        if (remaining === EmptyCoroutineContext) return element
        return CombinedContext(remaining, element)
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is CombinedContext) return false
        val count = fold<Int>(0) { size, _ -> size + 1 }
        val otherCount = other.fold<Int>(0) { size, _ -> size + 1 }
        return count == otherCount && fold<Boolean>(true) { matches, entry -> matches && other[entry.key] == entry }
    }

    override fun hashCode(): Int = left.hashCode() + element.hashCode()

    override fun toString(): String = "[" + fold<String>("") { text, entry ->
        if (text.isEmpty()) entry.toString() else text + ", " + entry.toString()
    } + "]"
}
