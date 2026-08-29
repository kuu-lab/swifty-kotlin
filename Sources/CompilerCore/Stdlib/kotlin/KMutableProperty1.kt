package kotlin

import kotlin.reflect.KMutableProperty1
import kotlin.reflect.KProperty

// KSP-800: Migrate the KMutableProperty1.setValue extension to bundled source.
// The implementation delegates directly to the existing property-reference setter.
@SinceKotlin("1.4")
public inline operator fun <T, V> KMutableProperty1<T, V>.setValue(
    thisRef: T,
    property: KProperty<*>,
    value: V
): Unit {
    set(thisRef, value)
}
