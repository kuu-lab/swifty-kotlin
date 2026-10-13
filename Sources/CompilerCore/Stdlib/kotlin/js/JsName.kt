/*
 * Copyright 2010-2018 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from Kotlin 2.3.10 commonMain/kotlin/JsAnnotationsH.kt.
 */
package kotlin.js

/** Records a declaration's JavaScript name in common source metadata. */
@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER
)
@OptIn(ExperimentalMultiplatform::class)
@OptionalExpectation
public expect annotation class JsName(val name: String)
