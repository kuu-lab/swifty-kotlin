@file:kotlin.jvm.JvmName("ArraysKt")

package kotlin.collections

public fun IntArray.sliceArray(indices: kotlin.ranges.IntRange): IntArray =
    if (indices.start > indices.endInclusive) IntArray(0)
    else copyOfRange(indices.start, indices.endInclusive + 1)
