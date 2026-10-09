/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Source compatibility surface derived from Kotlin 2.3.10's
 * libraries/stdlib/common/src/kotlin/JsAnnotationsH.kt and
 * libraries/stdlib/js/src/kotlin/annotationsJs.kt.
 */

package kotlin.js

/**
 * Marks an annotation as requiring an explicit opt-in before JavaScript
 * export is requested. The marker alone does not export a declaration.
 */
@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
@SinceKotlin("1.4")
public annotation class ExperimentalJsExport

/**
 * Marks the experimental JsFileName annotation.
 *
 * The marker is available to declarations that opt into the common API.
 * The Kotlin/JS actual JsFileName annotation itself does not require opt-in.
 */
@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
@SinceKotlin("1.9")
public annotation class ExperimentalJsFileName

/**
 * Specifies the name of the compiled file produced from the annotated source file.
 *
 * This annotation is accepted for source compatibility. JavaScript per-file
 * emission is provided by the Kotlin/JS backend and is not performed here.
 */
@Target(AnnotationTarget.FILE)
@Retention(AnnotationRetention.SOURCE)
@SinceKotlin("1.9")
public annotation class JsFileName(val name: String)

/**
 * Requests JavaScript export metadata for the annotated declaration.
 * JavaScript module emission is provided by the Kotlin/JS backend.
 */
@ExperimentalJsExport
@Retention(AnnotationRetention.BINARY)
@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.FILE
)
@SinceKotlin("1.3")
public annotation class JsExport
