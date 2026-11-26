@file:kotlin.jvm.JvmName("SequencesKt")
package kotlin.sequences

@kotlin.internal.InlineOnly
inline fun <T> Sequence<T>?.orEmpty(): Sequence<T> = this ?: emptySequence<T>()
