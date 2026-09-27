import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

private class Element : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<Element> {}
}

private class Alternate(override val key: CoroutineContext.Key<*>) : AbstractCoroutineContextElement(Element.Key) {
    companion object Key : CoroutineContext.Key<Alternate> {}
}

fun main() {
    val concrete = Element()
    val base: AbstractCoroutineContextElement = concrete
    println(concrete.key === Element.Key)
    println(base.key === Element.Key)
    val alternate: AbstractCoroutineContextElement = Alternate(Alternate.Key)
    println(alternate.key === Alternate.Key)
    println(alternate.key === Element.Key)
}
