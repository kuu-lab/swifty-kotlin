/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KVariance.kt.
 */

package kotlin.reflect

// KSP-1337: Keep KVariance source-backed so the generic enum pipeline owns
// entries, valueOf, and values using the Kotlin declaration order.
public enum class KVariance {
    INVARIANT,
    IN,
    OUT
}
