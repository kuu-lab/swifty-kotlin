package golden.sema

import kotlin.reflect.KMutableProperty1

class Counter(var value: Int)

fun <T, V> assign(property: KMutableProperty1<T, V>, receiver: T, value: V) {
    property.setValue(receiver, property, value)
}
