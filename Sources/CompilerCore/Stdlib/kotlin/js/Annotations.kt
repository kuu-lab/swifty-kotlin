/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Source compatibility surface derived from Kotlin 2.3.10's
 * libraries/stdlib/common/src/kotlin/JsAnnotationsH.kt and
 * libraries/stdlib/js/src/kotlin/annotationsJs.kt.
 */

package kotlin.js

import kotlin.reflect.KClass

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
@SinceKotlin("1.4")
public annotation class ExperimentalJsExport

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
@SinceKotlin("1.9")
public annotation class ExperimentalJsFileName

@Target(AnnotationTarget.FILE)
@Retention(AnnotationRetention.SOURCE)
@SinceKotlin("1.9")
public annotation class JsFileName(val name: String)

@ExperimentalJsExport
@Retention(AnnotationRetention.BINARY)
@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.FILE
)
@SinceKotlin("1.3")
public annotation class JsExport {
    @ExperimentalJsExport
    @Retention(AnnotationRetention.BINARY)
    @Target(
        AnnotationTarget.CLASS,
        AnnotationTarget.PROPERTY,
        AnnotationTarget.FUNCTION,
        AnnotationTarget.CONSTRUCTOR
    )
    @SinceKotlin("1.8")
    public annotation class Ignore

    @ExperimentalJsExport
    @Retention(AnnotationRetention.BINARY)
    @Target(
        AnnotationTarget.CLASS,
        AnnotationTarget.PROPERTY,
        AnnotationTarget.FUNCTION
    )
    @SinceKotlin("2.3")
    public annotation class Default
}

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
@SinceKotlin("2.0")
public annotation class ExperimentalJsStatic

@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
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
@MustBeDocumented
@SinceKotlin("1.9")
public annotation class ExperimentalJsReflectionCreateInstance

@ExperimentalJsStatic
@Retention(AnnotationRetention.BINARY)
@Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER
)
@MustBeDocumented
@SinceKotlin("2.0")
public annotation class JsStatic
