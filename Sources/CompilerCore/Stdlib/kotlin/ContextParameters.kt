/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/ContextParameters.kt.
 */

package kotlin

// KSP-733: the opt-in marker for context parameters, migrated out of the
// synthetic experimental-marker stubs in HeaderHelpers+SyntheticExperimentalMarkerStubs.swift.

@kotlin.RequiresOptIn(
    message = "The API is related to the experimental feature \"context parameters\" (see KEEP-367) and may be changed or removed in any future release.",
    level = RequiresOptIn.Level.ERROR
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
@kotlin.SinceKotlin("2.2")
public annotation class ExperimentalContextParameters

// KSP-603: the `context` / `contextOf` helpers migrated out of the synthetic
// stubs in HeaderHelpers+SyntheticScopeFunctionStubs.swift.
//
// Both are compiler intrinsics: `CallTypeChecker` binds the call to the
// declaration below and `CallLowerer` inline-expands it, substituting the
// context arguments for the block's context receivers and resolving `contextOf`
// against them. The bodies here only give the declarations a well-formed Kotlin
// shape; they are never executed.

@ExperimentalContextParameters
public inline fun <T, R> context(with: T, block: context(T) () -> R): R = block()

@ExperimentalContextParameters
public inline fun <A, B, R> context(a: A, b: B, block: context(A, B) () -> R): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, R> context(a: A, b: B, c: C, block: context(A, B, C) () -> R): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    block: context(A, B, C, D) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    block: context(A, B, C, D, E) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    block: context(A, B, C, D, E, F) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    block: context(A, B, C, D, E, F, G) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    block: context(A, B, C, D, E, F, G, H) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    block: context(A, B, C, D, E, F, G, H, I) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    block: context(A, B, C, D, E, F, G, H, I, J) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    block: context(A, B, C, D, E, F, G, H, I, J, K) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    o: O,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N, O) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    o: O,
    p: P,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    o: O,
    p: P,
    q: Q,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    o: O,
    p: P,
    q: Q,
    s: S,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, T, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    o: O,
    p: P,
    q: Q,
    s: S,
    t: T,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, T) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, T, U, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    o: O,
    p: P,
    q: Q,
    s: S,
    t: T,
    u: U,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, T, U) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, T, U, V, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    o: O,
    p: P,
    q: Q,
    s: S,
    t: T,
    u: U,
    v: V,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, T, U, V) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, T, U, V, W, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    h: H,
    i: I,
    j: J,
    k: K,
    l: L,
    m: M,
    n: N,
    o: O,
    p: P,
    q: Q,
    s: S,
    t: T,
    u: U,
    v: V,
    w: W,
    block: context(A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, S, T, U, V, W) () -> R
): R = block()

@ExperimentalContextParameters
public inline fun <A> contextOf(): A =
    throw IllegalStateException("contextOf() is expanded by the compiler")
