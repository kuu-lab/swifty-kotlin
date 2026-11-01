/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/ContextParameters.kt.
 */

package kotlin

@kotlin.RequiresOptIn(
    message = "The API is related to the experimental feature \"context parameters\" (see KEEP-367) and may be changed or removed in any future release.",
    level = RequiresOptIn.Level.ERROR
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
@kotlin.SinceKotlin("2.2")
public annotation class ExperimentalContextParameters

// KSP-603: `context` / `contextOf` are compiler intrinsics: `CallTypeChecker`
// binds the call to the declaration below and `CallLowerer` inline-expands it,
// substituting the context arguments for the block's context receivers and
// resolving `contextOf` against them. The bodies here only give the
// declarations a well-formed Kotlin shape; they are never executed.
//
// Upstream dropped `@ExperimentalContextParameters` from `context`/`contextOf`
// once the feature left the experimental gate: kotlin-stdlib 2.4.20 metadata
// carries only `InlineOnly`/`SinceKotlin` on these overloads, while the marker
// itself (and `KParameter.Kind.CONTEXT`) keeps `@RequiresOptIn`. Mirroring
// that split is what lets `context(...) { }` type-check without `@OptIn`
// while user-declared marker usages still report SEMA-OPT-IN (KUU-3781).

@kotlin.internal.InlineOnly
public inline fun <T, R> context(with: T, block: context(T) () -> R): R = block(with)

@kotlin.internal.InlineOnly
public inline fun <A, B, R> context(a: A, b: B, block: context(A, B) () -> R): R = block(a, b)

@kotlin.internal.InlineOnly
public inline fun <A, B, C, R> context(a: A, b: B, c: C, block: context(A, B, C) () -> R): R = block(a, b, c)

@kotlin.internal.InlineOnly
public inline fun <A, B, C, D, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    block: context(A, B, C, D) () -> R
): R = block(a, b, c, d)

@kotlin.internal.InlineOnly
public inline fun <A, B, C, D, E, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    block: context(A, B, C, D, E) () -> R
): R = block(a, b, c, d, e)

@kotlin.internal.InlineOnly
public inline fun <A, B, C, D, E, F, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    block: context(A, B, C, D, E, F) () -> R
): R = block(a, b, c, d, e, f)

@kotlin.internal.InlineOnly
public inline fun <A, B, C, D, E, F, G, R> context(
    a: A,
    b: B,
    c: C,
    d: D,
    e: E,
    f: F,
    g: G,
    block: context(A, B, C, D, E, F, G) () -> R
): R = block(a, b, c, d, e, f, g)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, s)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, s, t)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, s, t, u)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, s, t, u, v)

@kotlin.internal.InlineOnly
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
): R = block(a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, s, t, u, v, w)

@kotlin.internal.InlineOnly
public inline fun <A> contextOf(): A =
    throw IllegalStateException("contextOf() is expanded by the compiler")
