/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/OptIn.kt>.
 */

package kotlin

@kotlin.RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalSubclassOptIn
