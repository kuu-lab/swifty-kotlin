/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/ExperimentalStdlibApi.kt>.
 */

package kotlin

@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
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
    AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.MustBeDocumented
@kotlin.SinceKotlin("1.3")
public annotation class ExperimentalStdlibApi
