/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Collections.kt.
 */

package kotlin.collections

// KSP-697: the Collection shell is source-backed. Its residual members are
// still registered by the compiler for runtime dispatch compatibility.
public interface Collection<out E> : Iterable<E>
