/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/io/encoding/ExperimentalEncodingApi.kt>.
 */

package kotlin.io.encoding

/**
 * This annotation marks the experimental API for encoding and decoding between binary data and
 * printable ASCII character sequences.
 *
 * > Beware using the annotated API especially if you're developing a library, since your library might become binary incompatible
 * with the future versions of the standard library.
 *
 * Any usage of a declaration annotated with `@ExperimentalEncodingApi` must be accepted either
 * by annotating that usage with the [OptIn] annotation, e.g. `@OptIn(ExperimentalEncodingApi::class)`,
 * or by using the compiler argument `-opt-in=kotlin.io.encoding.ExperimentalEncodingApi`.
 */
@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
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
@kotlin.annotation.MustBeDocumented
@kotlin.SinceKotlin("1.8")
public annotation class ExperimentalEncodingApi
