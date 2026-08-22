/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/Annotations.kt>.
 */

package kotlin

/**
 * Suppresses a variance conflict for a type parameter used in an unsafe position.
 */
@kotlin.annotation.Target(AnnotationTarget.TYPE)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class UnsafeVariance
