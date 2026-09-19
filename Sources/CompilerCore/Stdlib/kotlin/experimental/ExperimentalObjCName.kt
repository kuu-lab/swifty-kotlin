/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/experimental/ExperimentalObjCName.kt>.
 */

package kotlin.experimental

@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
public annotation class ExperimentalObjCName
