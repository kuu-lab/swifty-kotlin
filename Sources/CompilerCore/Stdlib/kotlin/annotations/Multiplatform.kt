/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/Multiplatform.kt>.
 */

package kotlin

/**
 * The experimental multiplatform support API marker.
 *
 * Any usage of a declaration annotated with `@ExperimentalMultiplatform` must be accepted either
 * by annotating that usage with the [OptIn] annotation, e.g. `@OptIn(ExperimentalMultiplatform::class)`,
 * or by using the compiler argument `-opt-in=kotlin.ExperimentalMultiplatform`.
 */
@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalMultiplatform
