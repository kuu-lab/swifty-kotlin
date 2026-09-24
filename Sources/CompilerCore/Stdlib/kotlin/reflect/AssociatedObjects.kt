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

/**
 * If [T] is an @[AssociatedObjectKey]-annotated annotation class and [this] class is annotated with @[T] (`S::class`),
 * returns object `S`.
 *
 * Otherwise returns `null`.
 *
 * The compiler expands this declaration at a concrete call site to the
 * `__kk_kclass_find_associated_object` runtime entry (see
 * CallLowerer+KClassReflectMemberCalls.swift); the generic body itself is
 * never executed for a supported call shape, mirroring the enumValues
 * intrinsic pattern.
 */
@ExperimentalAssociatedObjects
public inline fun <reified T : Annotation> KClass<*>.findAssociatedObject(): Any? =
    throw NotImplementedError()
