/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/Annotations.kt>.
 */

package kotlin

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.ANNOTATION_CLASS,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.MustBeDocumented
@SinceKotlin("1.4")
public annotation class DeprecatedSinceKotlin(
    val warningSince: String = "",
    val errorSince: String = "",
    val hiddenSince: String = ""
)
