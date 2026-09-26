/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/typeOf.kt.
 */

package kotlin.reflect

// KSP-1323: source-backed kotlin.reflect surface, split out of the former
// Stdlib.kt grab-bag to follow the upstream per-declaration file layout.

/**
 * Returns a runtime representation of the given reified type [T] as an instance of [KType].
 */
public inline fun <reified T> typeOf(): KType =
    throw IllegalStateException("typeOf is expanded by the compiler")
