/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/Throws.kt>.
 */

package kotlin

import kotlin.reflect.KClass

/**
 * Marks the annotated declaration as throwing the specified checked exceptions.
 */
@kotlin.annotation.Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.CONSTRUCTOR,
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class Throws(public vararg val exceptionClasses: KClass<out Throwable>)
