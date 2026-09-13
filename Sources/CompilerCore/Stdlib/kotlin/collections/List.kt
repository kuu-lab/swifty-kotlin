/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Lists.kt.
 */

package kotlin.collections

// KSP-697: keep List's covariant nominal shell in Kotlin source. Indexed and
// iterator members remain compiler residuals in
// Sema/DataFlow/HeaderHelpers+SyntheticListResiduals.swift, which KSP-700 owns
// (KSP-699 covers only the collection factory functions).
public interface List<out E> : Collection<E>
