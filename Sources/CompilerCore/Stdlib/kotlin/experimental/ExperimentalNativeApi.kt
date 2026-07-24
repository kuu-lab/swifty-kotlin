/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/native-wasm/src/kotlin/experimental/Experimental.kt>.
 */
package kotlin.experimental

/**
 * Marks Kotlin/Native-only standard library API that is considered experimental
 * and requires an explicit opt-in.
 */
@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
@Retention(AnnotationRetention.BINARY)
@Target(
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
public annotation class ExperimentalNativeApi
