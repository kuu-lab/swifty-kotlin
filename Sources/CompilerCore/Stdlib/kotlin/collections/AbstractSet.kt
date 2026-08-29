/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractSet.kt.
 */

package kotlin.collections

// KSP-932: the nominal `AbstractSet<out E>` declaration is source-backed here;
// the compiler-side shell in `HeaderHelpers+SyntheticSetStubs.swift` remains
// the fallback for contexts without the bundled stdlib.

/**
 * Provides a skeletal implementation of the read-only [Set] interface.
 */
public abstract class AbstractSet<out E> protected constructor() : AbstractCollection<E>(), Set<E>
