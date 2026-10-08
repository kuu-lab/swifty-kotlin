import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.CoroutineContext as Context

// KUU-1597 Sema owner: pin inherited/overridden CoroutineContext.Key types; key identity checks stay in Scripts/diff_cases/stdlib_kotlin_coroutines_AbstractCoroutineContextElement_AbstractCoroutineContextElement_n.kt.
private class Element : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<Element> {}
}

private class Alternate : AbstractCoroutineContextElement(Element.Key) {
    companion object Key : Context.Key<Alternate> {}
    override val key: CoroutineContext.Key<*> get() = Alternate.Key
}

fun main() {
    val concrete: AbstractCoroutineContextElement = Element()
    val elementKey: CoroutineContext.Key<*> = concrete.key
    val alternate: AbstractCoroutineContextElement = Alternate()
    val alternateKey: CoroutineContext.Key<*> = alternate.key
}
