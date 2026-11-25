package kotlin

import kotlin.internal.KsSymbolName

public class DeepRecursiveScope<T, R> private constructor() {
    @KsSymbolName("__kk_deep_recursive_scope_callRecursive")
    public external suspend fun callRecursive(value: T): R

    @KsSymbolName("__kk_deep_recursive_function_callRecursive")
    public external suspend fun <U, S> DeepRecursiveFunction<U, S>.callRecursive(value: U): S

    @Deprecated(
        "Calling invoke directly from a DeepRecursiveScope is prohibited. Use callRecursive instead.",
        ReplaceWith("this.callRecursive(value)"),
        level = DeprecationLevel.ERROR
    )
    public operator fun DeepRecursiveFunction<*, *>.invoke(value: Any?): Nothing =
        throw UnsupportedOperationException("Should not be called from DeepRecursiveScope")
}

public class DeepRecursiveFunction<T, R> {
    @KsSymbolName("__kk_deep_recursive_function_new")
    public constructor(block: suspend DeepRecursiveScope<T, R>.(T) -> R)

    @KsSymbolName("__kk_deep_recursive_function_invoke")
    public external operator fun invoke(value: T): R

    @KsSymbolName("__kk_deep_recursive_function_callRecursive")
    public external suspend fun callRecursive(value: T): R
}
