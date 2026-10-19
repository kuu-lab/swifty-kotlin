/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/reflect/>.
 */

package kotlin.reflect

@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalAssociatedObjects

/**
 * The compiler expands this declaration at a concrete call site to the
 * `__kk_kclass_find_associated_object` runtime entry (see
 * CallLowerer+KClassReflectMemberCalls.swift); the generic body itself is
 * never executed for a supported call shape, mirroring the enumValues
 * intrinsic pattern.
 */
@ExperimentalAssociatedObjects
public inline fun <reified T : Annotation> KClass<*>.findAssociatedObject(): Any? =
    throw NotImplementedError()

@kotlin.reflect.ExperimentalAssociatedObjects
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
public annotation class AssociatedObjectKey
