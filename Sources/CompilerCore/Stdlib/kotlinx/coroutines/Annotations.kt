/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core/common/src/Annotations.kt.
 */
package kotlinx.coroutines

@kotlin.RequiresOptIn(level = kotlin.RequiresOptIn.Level.WARNING)
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
public annotation class ExperimentalCoroutinesApi

@kotlin.RequiresOptIn(level = kotlin.RequiresOptIn.Level.WARNING)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class DelicateCoroutinesApi

@kotlin.RequiresOptIn(level = kotlin.RequiresOptIn.Level.ERROR)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.TYPEALIAS,
    AnnotationTarget.PROPERTY
)
public annotation class InternalCoroutinesApi

@kotlin.RequiresOptIn(level = kotlin.RequiresOptIn.Level.WARNING)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.TYPEALIAS,
    AnnotationTarget.PROPERTY
)
public annotation class FlowPreview

@kotlin.RequiresOptIn(level = kotlin.RequiresOptIn.Level.WARNING)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.Target(AnnotationTarget.CLASS)
public annotation class ExperimentalForInheritanceCoroutinesApi

@kotlin.RequiresOptIn(level = kotlin.RequiresOptIn.Level.WARNING)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ObsoleteCoroutinesApi
