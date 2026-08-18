/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/OptIn.kt>.
 */

package kotlin

import kotlin.reflect.KClass

/**
 * Marks open and abstract classes and non-functional interfaces as requiring
 * an explicit opt-in before they can be subclassed or implemented.
 */
@kotlin.annotation.Target(AnnotationTarget.CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@SinceKotlin("2.1")
@WasExperimental(ExperimentalSubclassOptIn::class)
public annotation class SubclassOptInRequired(
    vararg val markerClass: KClass<out Annotation>
)
