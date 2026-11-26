package kotlin.collections

@kotlin.internal.InlineOnly
inline fun <T> Array<T>.plusElement(element: T): Array<T> = plus(element)

public fun IntArray.sliceArray(indices: kotlin.ranges.IntRange): IntArray = null!!
