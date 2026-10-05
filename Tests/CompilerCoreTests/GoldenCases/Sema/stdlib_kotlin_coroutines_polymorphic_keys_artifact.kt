@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package golden.sema

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.getPolymorphicElement
import kotlin.coroutines.minusPolymorphicKey

fun <E : CoroutineContext.Element> lookup(
    element: CoroutineContext.Element,
    key: CoroutineContext.Key<E>
): E? = element.getPolymorphicElement(key)

fun remove(element: CoroutineContext.Element, key: CoroutineContext.Key<*>): CoroutineContext =
    element.minusPolymorphicKey(key)
