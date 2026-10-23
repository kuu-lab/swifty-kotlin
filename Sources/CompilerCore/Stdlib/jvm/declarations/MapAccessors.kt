@file:kotlin.jvm.JvmName("MapAccessorsKt")

package kotlin.collections

operator fun <V, V1 : V> Map<in String, V>.getValue(
    thisRef: Any?,
    property: kotlin.reflect.KProperty<*>
): V1 = null!!

@kotlin.jvm.JvmName("getVar")
operator fun <V, V1 : V> MutableMap<in String, out V>.getValue(
    thisRef: Any?,
    property: kotlin.reflect.KProperty<*>
): V1 = null!!

operator fun <V> MutableMap<in String, in V>.setValue(
    thisRef: Any?,
    property: kotlin.reflect.KProperty<*>,
    value: V
) = null!!
