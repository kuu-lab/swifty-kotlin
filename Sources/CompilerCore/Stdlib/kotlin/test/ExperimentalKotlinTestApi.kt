/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-test <libraries/kotlin.test/common/src/main/kotlin/kotlin/test/ExperimentalKotlinTestApi.kt>.
 */

package kotlin.test

// KUU-1693 requests this Kotlin 2.4 marker as a compatibility extension to the
// Kotlin 2.3.10 surface. Omit SinceKotlin("2.4") so it is usable on that target.
/** Marks experimental kotlin.test APIs that require explicit opt-in. */
@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@Retention(AnnotationRetention.BINARY)
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.ANNOTATION_CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FIELD,
    AnnotationTarget.LOCAL_VARIABLE,
    AnnotationTarget.VALUE_PARAMETER,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.TYPEALIAS
)
@MustBeDocumented
public annotation class ExperimentalKotlinTestApi
