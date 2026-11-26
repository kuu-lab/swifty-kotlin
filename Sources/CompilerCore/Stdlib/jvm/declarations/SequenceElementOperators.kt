@file:kotlin.jvm.JvmName("SequencesKt")
package kotlin.sequences

@kotlin.internal.InlineOnly
inline fun <T> Sequence<T>.plusElement(element: T): Sequence<T> = plus(element)
