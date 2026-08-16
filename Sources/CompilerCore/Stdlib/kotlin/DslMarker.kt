/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/DslMarker.kt>.
 */

package kotlin

/**
 * When applied to annotation class [A] marks API as a domain-specific language.
 *
 * When applied to a type [T], indicates that [T] is a part of DSL and calls to [T]'s members
 * can be made only without an implicit receiver (i.e. an implicit receiver from the outer scope
 * is not available for those calls).
 */
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
@kotlin.SinceKotlin("1.1")
public annotation class DslMarker
