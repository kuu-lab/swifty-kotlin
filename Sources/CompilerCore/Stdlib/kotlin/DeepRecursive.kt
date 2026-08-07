/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/DeepRecursive.kt.
 */

package kotlin

import kotlin.internal.KsSymbolName

// KSP-612: DeepRecursiveFunction / DeepRecursiveScope declarations migrated out
// of HeaderHelpers+SyntheticDeepRecursiveStubs.swift. The trampoline itself
// stays in the Swift runtime (RuntimeDeepRecursive.swift) behind four `__kk_`
// bridges — that trampoline is the whole reason the API exists, so it is not
// expressible as pure Kotlin here.
//
// Deviations from the stdlib signatures, forced by the current compiler model:
// - `callRecursive` is a plain member of DeepRecursiveScope rather than a
//   suspend member extension, because FunctionSignature models a single
//   explicit receiver.
// - the block is a non-suspend receiver lambda: recursion is trampolined by the
//   runtime, not by the CPS state machine.

/**
 * A scope passed to the block of a [DeepRecursiveFunction]. Instances are
 * created by the runtime trampoline for each invocation; the class itself only
 * declares the recursion entry point.
 */
public class DeepRecursiveScope<T, R> internal constructor() {
    @KsSymbolName("__kk_deep_recursive_scope_callRecursive")
    public external fun callRecursive(value: T): R
}

/**
 * A recursive function that runs on a runtime-managed stack, so recursion depth
 * is bounded by the heap rather than by the native stack.
 */
public class DeepRecursiveFunction<T, R> {
    /**
     * The runtime owns the instance: the bridge registers the block's entry
     * point plus its captured environment and returns the resulting handle.
     */
    @KsSymbolName("__kk_deep_recursive_function_new")
    constructor(block: DeepRecursiveScope<T, R>.(T) -> R)

    @KsSymbolName("__kk_deep_recursive_function_invoke")
    public external operator fun invoke(value: T): R

    @KsSymbolName("__kk_deep_recursive_function_callRecursive")
    public external fun callRecursive(value: T): R
}
