/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/Annotation.kt>.
 */

package kotlin

// KSP-719: nominal kotlin.Annotation declaration migrated to bundled source.
// The existing synthetic placeholder in registerSyntheticAnyStub is reused on
// bundle load so early type-system wiring (annotation class supertypes,
// BuiltinTypeNames, findAssociatedObject bound) keeps resolving.
public interface Annotation {}
