package golden.sema

import kotlin.reflect.KMutableProperty0

var topLevel: Int = 0

fun <V> assignWithSetValue(property: KMutableProperty0<V>, value: V) {
    property.setValue(null, property, value)
}
