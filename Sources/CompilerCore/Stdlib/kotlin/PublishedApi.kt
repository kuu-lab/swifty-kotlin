/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/PublishedApi.kt>.
 */

package kotlin

/**
 * When applied to a class or a member with internal visibility allows using it from public inline functions and
 * makes it effectively public.
 *
 * Public inline functions cannot use non-public API, since if they are inlined, those non-public API references
 * would violate access restrictions at a call site (see restrictions for public API inline functions).
 *
 * To overcome this restriction an `internal` declaration can be annotated with the `@PublishedApi` annotation:
 * - this allows calling that declaration from public inline functions;
 * - the declaration becomes effectively public, and this should be considered with respect to binary compatibility maintaining.
 */
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
@SinceKotlin("1.1")
public annotation class PublishedApi()
