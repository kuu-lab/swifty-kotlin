package kotlin.sequences

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public fun <T> Sequence<T>.allEqual(): Boolean = asIterable().allEqual()

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public inline fun <T, K> Sequence<T>.allEqualBy(selector: (T) -> K): Boolean =
    asIterable().allEqualBy(selector)

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public fun <T> Sequence<T>.allDistinct(): Boolean = asIterable().allDistinct()

@SinceKotlin("2.4")
@ExperimentalStdlibApi
public inline fun <T, K> Sequence<T>.allDistinctBy(selector: (T) -> K): Boolean =
    asIterable().allDistinctBy(selector)
