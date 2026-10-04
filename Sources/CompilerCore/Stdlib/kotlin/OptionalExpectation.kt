/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/Multiplatform.kt>.
 */

package kotlin

/**
 * Marks a top-level declaration in a common module as an optional expected declaration in a multiplatform project.
 *
 * Such declarations are expected to have corresponding platform-specific implementations in all platforms,
 * but if an implementation is missing, the compiler will not produce an error.
 */
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.ExperimentalMultiplatform
public annotation class OptionalExpectation
