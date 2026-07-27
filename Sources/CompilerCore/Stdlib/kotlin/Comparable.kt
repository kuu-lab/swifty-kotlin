/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib core/builtins/native/kotlin/Comparable.kt.
 */

package kotlin

// KSP-669: nominal `kotlin.Comparable<in T>` declaration migrated out of the
// synthetic self-registration; on bundle load it reuses the synthetic shell.
// `compareTo` is intentionally omitted here — it stays a compiler residual
// (bare type-parameter receiver, alongside the c-hard primitive conformances) so
// member calls on `T : Comparable<T>`-bounded type parameters keep resolving.
public interface Comparable<in T>
