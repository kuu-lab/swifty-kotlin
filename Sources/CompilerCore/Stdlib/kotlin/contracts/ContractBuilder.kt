/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/contracts/ContractBuilder.kt.
 */

package kotlin.contracts

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

/** Describes an effect observed when a Boolean condition holds. */
@ExperimentalContracts
@ExperimentalExtendedContracts
public infix fun Boolean.implies(value: ReturnsNotNull) {}

/** Describes a condition guaranteed to hold while a lambda executes. */
@ExperimentalContracts
@ExperimentalExtendedContracts
public infix fun <R> Boolean.holdsIn(lambda: Function<R>): HoldsIn =
    TODO("Contract effects are compiler-only")

/** Declares the contract of a function. */
@ExperimentalContracts
@SinceKotlin("1.3")
public inline fun contract(builder: ContractBuilder.() -> Unit) {}
