@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.coroutines.AbstractCoroutineContextKey
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.coroutines.getPolymorphicElement
import kotlin.coroutines.minusPolymorphicKey

object BaseKey : CoroutineContext.Key<BaseElement>
object OtherKey : CoroutineContext.Key<BaseElement>

open class BaseElement : CoroutineContext.Element {
    override val key: CoroutineContext.Key<*> = BaseKey
    override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? =
        getPolymorphicElement(key)
    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext = minusPolymorphicKey(key)
}

class DerivedElement : BaseElement()

object DerivedKey : AbstractCoroutineContextKey<BaseElement, DerivedElement>(
    BaseKey, { element -> element as? DerivedElement }
)

object ChainedKey : AbstractCoroutineContextKey<DerivedElement, DerivedElement>(
    DerivedKey, { element -> element as? DerivedElement }
)

var unrelatedCasts = 0
object UnrelatedKey : AbstractCoroutineContextKey<BaseElement, DerivedElement>(
    OtherKey, { element ->
        unrelatedCasts += 1
        element as? DerivedElement
    }
)

object RejectingKey : AbstractCoroutineContextKey<BaseElement, DerivedElement>(BaseKey, { _ -> null })

class EqualKey : CoroutineContext.Key<PlainElement> {
    override fun equals(other: Any?): Boolean = other is EqualKey
    override fun hashCode(): Int = 0
}

class PlainElement(override val key: CoroutineContext.Key<*>) : CoroutineContext.Element

object PlainPolymorphicKey : AbstractCoroutineContextKey<PlainElement, PlainElement>(
    EqualKey(), { element -> element as? PlainElement }
)

object ChainedPlainKey : AbstractCoroutineContextKey<PlainElement, PlainElement>(
    PlainPolymorphicKey, { element -> element as? PlainElement }
)

class PolymorphicKeyElement(override val key: CoroutineContext.Key<*>) : BaseElement()

fun main() {
    val element: CoroutineContext.Element = DerivedElement()
    val derived: DerivedElement? = element.getPolymorphicElement(DerivedKey)
    println(element.getPolymorphicElement(BaseKey) === element)
    println(derived === element)
    println(element.getPolymorphicElement(ChainedKey) === element)
    println(element.getPolymorphicElement(OtherKey) == null)
    println(element.getPolymorphicElement(UnrelatedKey) == null)
    println(element.getPolymorphicElement(RejectingKey) == null)
    println(element.minusPolymorphicKey(BaseKey) === EmptyCoroutineContext)
    println(element.minusPolymorphicKey(DerivedKey) === EmptyCoroutineContext)
    println(element.minusPolymorphicKey(ChainedKey) === EmptyCoroutineContext)
    println(element.minusPolymorphicKey(OtherKey) === element)
    println(element.minusPolymorphicKey(UnrelatedKey) === element)
    println(element.minusPolymorphicKey(RejectingKey) === element)
    println(unrelatedCasts)

    val plain: CoroutineContext.Element = BaseElement()
    println(plain.getPolymorphicElement(DerivedKey) == null)
    println(plain.minusPolymorphicKey(DerivedKey) === plain)

    val delegated: BaseElement = DerivedElement()
    println(delegated[DerivedKey] === delegated)
    println(delegated[ChainedKey] === delegated)
    println(delegated.minusKey(DerivedKey) === EmptyCoroutineContext)
    println(delegated.minusKey(ChainedKey) === EmptyCoroutineContext)

    val key = EqualKey()
    val equalKey = EqualKey()
    val identity: CoroutineContext.Element = PlainElement(key)
    println(key == equalKey)
    println(identity.getPolymorphicElement(key) === identity)
    println(identity.getPolymorphicElement(equalKey) == null)
    println(identity.minusPolymorphicKey(key) === EmptyCoroutineContext)
    println(identity.minusPolymorphicKey(equalKey) === identity)

    val selfKeyed: CoroutineContext.Element = PlainElement(PlainPolymorphicKey)
    println(selfKeyed.getPolymorphicElement(PlainPolymorphicKey) === selfKeyed)
    println(selfKeyed.minusPolymorphicKey(PlainPolymorphicKey) === EmptyCoroutineContext)
    println(selfKeyed.getPolymorphicElement(ChainedPlainKey) == null)
    println(selfKeyed.minusPolymorphicKey(ChainedPlainKey) === selfKeyed)

    val keyed: CoroutineContext.Element = PolymorphicKeyElement(RejectingKey)
    println(keyed.getPolymorphicElement(RejectingKey) == null)
    println(keyed.minusPolymorphicKey(RejectingKey) === keyed)
}
