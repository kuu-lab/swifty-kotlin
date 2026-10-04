package golden.sema

import kotlin.coroutines.CoroutineContext

fun elementKey(element: CoroutineContext.Element): CoroutineContext.Key<*> = element.key

fun <E : CoroutineContext.Element> elementGet(element: CoroutineContext.Element, key: CoroutineContext.Key<E>): E? =
    element[key]

fun elementFold(element: CoroutineContext.Element): Int =
    element.fold(5) { value, _ -> value + 1 }

fun elementMinusKey(element: CoroutineContext.Element, key: CoroutineContext.Key<*>): CoroutineContext =
    element.minusKey(key)
