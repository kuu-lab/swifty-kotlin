/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/PublishedApi.kt>.
 */

package kotlin

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
@SinceKotlin("1.1")
public annotation class PublishedApi()
