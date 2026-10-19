/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/>.
 */

package kotlin

@kotlin.RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@kotlin.annotation.MustBeDocumented
@kotlin.annotation.Target(
    AnnotationTarget.CLASS, AnnotationTarget.ANNOTATION_CLASS,
    AnnotationTarget.PROPERTY, AnnotationTarget.FIELD, AnnotationTarget.LOCAL_VARIABLE,
    AnnotationTarget.VALUE_PARAMETER, AnnotationTarget.CONSTRUCTOR, AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.PROPERTY_SETTER, AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalUnsignedTypes
