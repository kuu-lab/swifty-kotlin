/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/contracts/Effect.kt.
 */

package kotlin.contracts

/** Compatibility root for the historical contract effect hierarchy. */
@ExperimentalContracts
@SinceKotlin("1.3")
public interface ContractEffect

/** An observable effect of a function invocation. */
@ExperimentalContracts
@SinceKotlin("1.3")
public interface Effect : ContractEffect

/** An effect that is observed when a condition becomes true. */
@ExperimentalContracts
@SinceKotlin("1.3")
public interface ConditionalEffect : Effect

/** An effect that can be observed after a function invocation. */
@ExperimentalContracts
@SinceKotlin("1.3")
public interface SimpleEffect : Effect {
    /** Attaches a boolean condition to this effect. */
    @ExperimentalContracts
    public infix fun implies(booleanExpression: Boolean): ConditionalEffect
}

/** Describes a normal return with a given value. */
@ExperimentalContracts
@SinceKotlin("1.3")
public interface Returns : SimpleEffect

/** Describes a normal return with any non-null value. */
@ExperimentalContracts
@SinceKotlin("1.3")
public interface ReturnsNotNull : SimpleEffect

/** Describes a function parameter called in place. */
@ExperimentalContracts
@SinceKotlin("1.3")
public interface CallsInPlace : Effect

/** Describes a condition guaranteed to hold in a lambda body. */
@ExperimentalContracts
@ExperimentalExtendedContracts
@SinceKotlin("2.2")
public interface HoldsIn : Effect
