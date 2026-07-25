/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/reflect/>.
 */

package kotlin.reflect

/**
 * The experimental marker for the associated objects reflection API.
 *
 * Any usage of a declaration annotated with `@ExperimentalAssociatedObjects` must be accepted either
 * by annotating that usage with the [OptIn] annotation, e.g. `@OptIn(ExperimentalAssociatedObjects::class)`,
 * or by using the compiler argument `-opt-in=kotlin.reflect.ExperimentalAssociatedObjects`.
 */
@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalAssociatedObjects
