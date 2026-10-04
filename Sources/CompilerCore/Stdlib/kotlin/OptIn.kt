/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/OptIn.kt>.
 */

package kotlin

import kotlin.reflect.KClass

/**
 * Allows to use the API denoted by the given markers in the annotated file, declaration, or expression.
 * If a declaration is annotated with [OptIn], its usages are **not** required to opt in to that API.
 *
 * See also [Kotlin language documentation](https://kotlinlang.org/docs/opt-in-requirements.html) for more information.
 */
@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.LOCAL_VARIABLE,
    AnnotationTarget.VALUE_PARAMETER,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.EXPRESSION,
    AnnotationTarget.FILE,
    AnnotationTarget.TYPEALIAS,
)
@kotlin.annotation.Retention(AnnotationRetention.SOURCE)
@SinceKotlin("1.3")
public annotation class OptIn(
    vararg val markerClass: KClass<out Annotation>
)
