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

@ExperimentalContracts
@SinceKotlin("1.3")
public interface Effect : ContractEffect

@ExperimentalContracts
@SinceKotlin("1.3")
public interface ConditionalEffect : Effect

@ExperimentalContracts
@SinceKotlin("1.3")
public interface SimpleEffect : Effect {
    @ExperimentalContracts
    public infix fun implies(booleanExpression: Boolean): ConditionalEffect
}

@ExperimentalContracts
@SinceKotlin("1.3")
public interface Returns : SimpleEffect

@ExperimentalContracts
@SinceKotlin("1.3")
public interface ReturnsNotNull : SimpleEffect

@ExperimentalContracts
@SinceKotlin("1.3")
public interface CallsInPlace : Effect

@ExperimentalContracts
@ExperimentalExtendedContracts
@SinceKotlin("2.2")
public interface HoldsIn : Effect
