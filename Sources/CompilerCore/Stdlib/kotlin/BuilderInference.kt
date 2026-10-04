/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/BuilderInference.kt>.
 */
package kotlin

@kotlin.annotation.Target(
    AnnotationTarget.VALUE_PARAMETER,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.experimental.ExperimentalTypeInference
public annotation class BuilderInference
