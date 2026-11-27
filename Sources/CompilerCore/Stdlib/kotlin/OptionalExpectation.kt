/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/Multiplatform.kt>.
 */

package kotlin

@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.ExperimentalMultiplatform
public annotation class OptionalExpectation
