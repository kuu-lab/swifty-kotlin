package kotlin

import kotlin.internal.KsSymbolName

// KSP-612 / KUU-642: kotlin.DeepRecursiveFunction / kotlin.DeepRecursiveScope
// migrated to bundled Kotlin source. Both types are opaque runtime handles.
//
// The block is the suspend receiver lambda
// `suspend DeepRecursiveScope<T, R>.(T) -> R` required by Kotlin's public API.
// `callRecursive` is a suspend point: the compiler splits the block into a
// state machine, and the runtime trampoline
// (Sources/Runtime/RuntimeDeepRecursive.swift) starts a fresh coroutine for
// each recursive step instead of consuming a native stack frame.

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
