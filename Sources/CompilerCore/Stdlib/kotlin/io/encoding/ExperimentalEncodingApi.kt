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
 * Any usage of a declaration annotated with `@ExperimentalEncodingApi` must be accepted either
 * by annotating that usage with the [OptIn] annotation, e.g. `@OptIn(ExperimentalEncodingApi::class)`,
 * or by using the compiler argument `-opt-in=kotlin.io.encoding.ExperimentalEncodingApi`.
 */
@kotlin.RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ExperimentalEncodingApi
