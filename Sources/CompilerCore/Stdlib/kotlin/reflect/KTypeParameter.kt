/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KTypeParameter.kt.
 */

package kotlin.reflect

// KSP-1323/KSP-1333: source-backed KTypeParameter surface. Concrete
// implementations dispatch the abstract properties through the interface itable.

/**
 * Represents a type parameter of a generic declaration.
 */
public interface KTypeParameter : KClassifier {
    public val name: String

    public val upperBounds: List<KType>

    public val variance: KVariance

    public val isReified: Boolean
}
