/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/SinceKotlin.kt>.
 */

package kotlin

/**
 * Signifies that the annotated element is available since the specified version.
 */
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FIELD,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
public annotation class SinceKotlin(val version: String)
