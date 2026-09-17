/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/contracts/ContractBuilder.kt.
 */

package kotlin.contracts

/** Marker for the experimental contract declaration API. */
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.SinceKotlin("1.3")
@kotlin.RequiresOptIn
@kotlin.annotation.MustBeDocumented
public annotation class ExperimentalContracts

/** Marker for the experimental extended contract declaration API. */
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.SinceKotlin("2.2")
@kotlin.RequiresOptIn
@kotlin.annotation.MustBeDocumented
public annotation class ExperimentalExtendedContracts

/** Scope containing the contract declaration DSL. */
@ExperimentalContracts
@SinceKotlin("1.3")
public interface ContractBuilder {
    /** Describes a normal return without an exception. */
    @IgnorableReturnValue
    public fun returns(): Returns

    /** Describes a normal return with the specified value. */
    @IgnorableReturnValue
    public fun returns(value: Any?): Returns

    /** Describes a normal return with any non-null value. */
    @IgnorableReturnValue
    public fun returnsNotNull(): ReturnsNotNull

    /** Describes how often a lambda parameter is called in place. */
    @IgnorableReturnValue
    public fun <R> callsInPlace(
        lambda: Function<R>,
        kind: InvocationKind = InvocationKind.UNKNOWN
    ): CallsInPlace
}

/** Describes a condition guaranteed to hold while a lambda executes. */
@ExperimentalContracts
@ExperimentalExtendedContracts
public infix fun <R> Boolean.holdsIn(lambda: Function<R>): HoldsIn =
    TODO("Contract effects are compiler-only")

/** Specifies how many times a function invokes a lambda parameter in place. */
@ExperimentalContracts
@SinceKotlin("1.3")
public enum class InvocationKind {
    AT_MOST_ONCE,
    AT_LEAST_ONCE,
    EXACTLY_ONCE,
    UNKNOWN
}

/** Declares the contract of a function. */
@ExperimentalContracts
@SinceKotlin("1.3")
public inline fun contract(builder: ContractBuilder.() -> Unit) {}
