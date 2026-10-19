package kotlin

import kotlin.reflect.KMutableProperty1
import kotlin.reflect.KProperty

@SinceKotlin("1.4")
public inline operator fun <T, V> KMutableProperty1<T, V>.setValue(
    thisRef: T,
    property: KProperty<*>,
    value: V
): Unit {
    set(thisRef, value)
}
