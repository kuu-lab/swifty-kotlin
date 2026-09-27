import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.CoroutineContext as Context

private class Element : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<Element> {}
}

private class Alternate : AbstractCoroutineContextElement(Element.Key) {
    companion object Key : Context.Key<Alternate> {}
    override val key: CoroutineContext.Key<*> get() = Alternate.Key
}

fun main() {
    val concrete = Element()
    val base: AbstractCoroutineContextElement = concrete
    println(concrete.key === Element.Key)
    println(base.key === Element.Key)
    val alternate: AbstractCoroutineContextElement = Alternate()
    println(alternate.key === Alternate.Key)
    println(alternate.key === Element.Key)
}
