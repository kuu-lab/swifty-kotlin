package kotlin.collections

public fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.foldTo(
    destination: M,
    initialValueSelector: (K, T) -> R,
    operation: (K, R, T) -> R
): M = null!!

public fun <T, K, R, M : MutableMap<in K, R>> Grouping<T, K>.foldTo(
    destination: M,
    initialValue: R,
    operation: (R, T) -> R
): M = null!!
