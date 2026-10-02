/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/reflect/>.
 */

package kotlin.reflect

// KSP-1323: source-backed kotlin.reflect surface, split out of the former
// Stdlib.kt grab-bag to follow the upstream per-declaration file layout.

/**
 * Represents an entity which may contain declarations of other entities.
 */
public interface KDeclarationContainer
