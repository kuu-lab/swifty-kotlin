@file:kotlin.jvm.JvmName("CollectionsKt")
package kotlin.collections

@kotlin.internal.InlineOnly
inline fun <T> List<T>?.orEmpty(): List<T> = this ?: emptyList<T>()
