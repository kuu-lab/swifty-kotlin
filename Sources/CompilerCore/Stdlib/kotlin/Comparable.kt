/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib core/builtins/native/kotlin/Comparable.kt.
 */

package kotlin

import kotlin.internal.KsSymbolName

// KSP-797: source-backed `compareTo` declaration. The runtime bridge performs
// erased Comparable dispatch after source-level member resolution.
public interface Comparable<in T> {
    @KsSymbolName("__kk_comparable_compareTo")
    public external operator fun compareTo(other: T): Int
}
