@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

/**
 * Creates a new [AtomicArray] filled with elements of the given [array].
 *
 * This overload is an internal stdlib implementation entry point in Kotlin's
 * Native source and is kept out of consumer metadata. The runtime bridge
 * (`kk_atomic_ref_array_of`) copies the elements into fresh storage, matching
 * the `array.copyOf()` semantics of the Kotlin/Native declaration.
 */
@SinceKotlin("1.9")
@ExperimentalStdlibApi
@PublishedApi
internal fun <T> AtomicArray(array: Array<T>): AtomicArray<T> = atomicArrayFromArray(array)
