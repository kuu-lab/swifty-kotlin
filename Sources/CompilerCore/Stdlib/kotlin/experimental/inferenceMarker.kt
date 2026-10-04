/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/experimental/inferenceMarker.kt>.
 */
package kotlin.experimental

/**
 * The experimental marker for type inference augmenting annotations.
 */
@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.ANNOTATION_CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.TYPE,
    AnnotationTarget.TYPEALIAS
)
@Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalTypeInference
