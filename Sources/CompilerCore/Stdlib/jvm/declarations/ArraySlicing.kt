package kotlin.collections

@kotlin.internal.InlineOnly
inline fun <T> Array<T>.plusElement(element: T): Array<T> = plus(element)

public fun IntArray.sliceArray(indices: kotlin.ranges.IntRange): IntArray = null!!

@kotlin.internal.InlineOnly
inline fun <reified T> Array<out T>?.orEmpty(): Array<out T> = this ?: emptyArray<T>()
