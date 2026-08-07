/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/contextParameters/Context.kt>
 * and <libraries/stdlib/src/kotlin/contextParameters/ContextOf.kt>.
 */
package kotlin

// KSP-603: `context` / `contextOf` declarations migrated from the synthetic
// stubs in HeaderHelpers+SyntheticScopeFunctionStubs.swift.
//
// Both are compiler intrinsics: `context(...)` call sites bind their arguments
// as context receiver values around the block body and `contextOf<A>()` reads
// the matching value back (CallTypeChecker / CallLowerer). The declarations
// below therefore only carry the signature and the opt-in marker; the bodies
// are never reached from a call site.

@ExperimentalContextParameters
public inline fun <T, R> context(with: T, block: context(T) () -> R): R = block()

@ExperimentalContextParameters
public inline fun <A, B, Result> context(a: A, b: B, block: context(A, B) () -> Result): Result = block()

@ExperimentalContextParameters
public inline fun <A, B, C, Result> context(a: A, b: B, c: C, block: context(A, B, C) () -> Result): Result = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, Result> context(
    a: A,
    b: B,
    c: C,
    d: D,
    block: context(A, B, C, D) () -> Result
): Result = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, Result> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    block: context(A, B, C, D, E) () -> Result
): Result = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, Result> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    block: context(A, B, C, D, E, F) () -> Result
): Result = block()

@ExperimentalContextParameters
public inline fun <A> contextOf(): A =
    throw UnsupportedOperationException("contextOf<A>() is expanded by the compiler")
