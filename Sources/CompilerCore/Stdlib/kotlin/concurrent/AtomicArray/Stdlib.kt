@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

@SinceKotlin("1.9")
@ExperimentalStdlibApi
@PublishedApi
internal fun <T> AtomicArray(array: Array<T>): AtomicArray<T> = atomicArrayFromArray(array)
