/*
 * Copyright 2010-2022 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/OptIn.kt>.
 */

package kotlin

import kotlin.reflect.KClass

/**
 * Annotation that marks open for subclassing classes and interfaces, and makes implementation
 * and extension of such declarations as requiring an explicit opt-in.
 *
 * When applied, any attempt to subclass the target declaration will trigger an opt-in
 * with the corresponding level and message.
 *
 * @property markerClass specifies marker annotation that require explicit opt-in.
 * @see RequiresOptIn for a detailed description of opt-in semantics and propagation rules.
 */
@kotlin.annotation.Target(AnnotationTarget.CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.SinceKotlin("2.1")
@kotlin.WasExperimental(ExperimentalSubclassOptIn::class)
public annotation class SubclassOptInRequired(
    vararg val markerClass: KClass<out Annotation>,
)
