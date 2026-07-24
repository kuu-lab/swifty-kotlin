/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/OptIn.kt>.
 */

package kotlin

/**
 * This annotation marks the experimental preview of the language feature `SubclassOptInRequired`.
 *
 * Any usage of a declaration annotated with `@ExperimentalSubclassOptIn` must be accepted either
 * by annotating that usage with the [OptIn] annotation, e.g. `@OptIn(ExperimentalSubclassOptIn::class)`,
 * or by using the compiler argument `-opt-in=kotlin.ExperimentalSubclassOptIn`.
 */
@kotlin.RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalSubclassOptIn
