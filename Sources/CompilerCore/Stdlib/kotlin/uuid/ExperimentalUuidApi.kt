/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/uuid/ExperimentalUuidApi.kt>.
 */

package kotlin.uuid

/**
 * This annotation marks the experimental Kotlin Uuid API.
 *
 * Any usage of a declaration annotated with `@ExperimentalUuidApi` must be accepted either
 * by annotating that usage with the [OptIn] annotation, e.g. `@OptIn(ExperimentalUuidApi::class)`,
 * or by using the compiler argument `-opt-in=kotlin.uuid.ExperimentalUuidApi`.
 */
@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.ANNOTATION_CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FIELD,
    AnnotationTarget.LOCAL_VARIABLE,
    AnnotationTarget.VALUE_PARAMETER,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.TYPEALIAS,
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalUuidApi
