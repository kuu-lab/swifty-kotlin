/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/contracts/ContractBuilder.kt.
 */

package kotlin.contracts

/** Marker for the experimental contract declaration API. */
@Retention(AnnotationRetention.BINARY)
@SinceKotlin("1.3")
@RequiresOptIn
@MustBeDocumented
public annotation class ExperimentalContracts

/** Marker for the experimental extended contract declaration API. */
@Retention(AnnotationRetention.BINARY)
@SinceKotlin("2.2")
@RequiresOptIn
@MustBeDocumented
public annotation class ExperimentalExtendedContracts

/** Specifies how many times a function invokes a lambda parameter in place. */
@ExperimentalContracts
@SinceKotlin("1.3")
public enum class InvocationKind {
    AT_MOST_ONCE,
    AT_LEAST_ONCE,
    EXACTLY_ONCE,
    UNKNOWN
}
