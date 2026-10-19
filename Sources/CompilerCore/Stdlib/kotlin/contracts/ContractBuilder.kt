/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/contracts/ContractBuilder.kt.
 */

package kotlin.contracts

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

@ExperimentalContracts
@SinceKotlin("1.3")
public interface ContractBuilder {
    @IgnorableReturnValue
    public fun returns(): Returns

    @IgnorableReturnValue
    public fun returns(value: Any?): Returns

    @IgnorableReturnValue
    public fun returnsNotNull(): ReturnsNotNull

    @IgnorableReturnValue
    public fun <R> callsInPlace(
        lambda: Function<R>,
        kind: InvocationKind = InvocationKind.UNKNOWN
    ): CallsInPlace
}

@ExperimentalContracts
@ExperimentalExtendedContracts
public infix fun <R> Boolean.holdsIn(lambda: Function<R>): HoldsIn =
    TODO("Contract effects are compiler-only")

@ExperimentalContracts
@SinceKotlin("1.3")
public enum class InvocationKind {
    AT_MOST_ONCE,
    AT_LEAST_ONCE,
    EXACTLY_ONCE,
    UNKNOWN
}

@ExperimentalContracts
@SinceKotlin("1.3")
public inline fun contract(builder: ContractBuilder.() -> Unit) {}
