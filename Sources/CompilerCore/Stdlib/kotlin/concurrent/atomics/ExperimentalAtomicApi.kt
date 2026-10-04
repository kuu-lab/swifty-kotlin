/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/ExperimentalAtomicApi.kt>.
 */

package kotlin.concurrent.atomics

import kotlin.annotation.AnnotationTarget.*

/**
 * This annotation marks the experimental Kotlin Atomics API.
 *
 * Any usage of a declaration annotated with `@ExperimentalAtomicApi` must be accepted either by
 * annotating that usage with the [OptIn] annotation, e.g. `@OptIn(ExperimentalAtomicApi::class)`,
 * or by using the compiler argument `-opt-in=kotlin.concurrent.atomics.ExperimentalAtomicApi`.
 */
@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@Retention(AnnotationRetention.BINARY)
@Target(
    CLASS,
    ANNOTATION_CLASS,
    PROPERTY,
    FIELD,
    LOCAL_VARIABLE,
    VALUE_PARAMETER,
    CONSTRUCTOR,
    FUNCTION,
    PROPERTY_GETTER,
    PROPERTY_SETTER,
    TYPEALIAS
)
@MustBeDocumented
@SinceKotlin("2.1")
public annotation class ExperimentalAtomicApi
