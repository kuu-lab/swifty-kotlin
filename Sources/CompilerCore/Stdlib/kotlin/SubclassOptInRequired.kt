/*
 * Copyright 2010-2022 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/OptIn.kt>.
 */

package kotlin

import kotlin.reflect.KClass

@kotlin.annotation.Target(AnnotationTarget.CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.SinceKotlin("2.1")
@kotlin.WasExperimental(ExperimentalSubclassOptIn::class)
public annotation class SubclassOptInRequired(
    vararg val markerClass: KClass<out Annotation>,
)
