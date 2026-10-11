/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from Kotlin 2.3.10 commonMain/kotlin/JvmAnnotationsH.kt.
 */
package kotlin.jvm

/** Records the common declaration's JVM synthetic intent; it does not emit Java bytecode here. */
@Target(
    AnnotationTarget.FILE,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.FIELD
)
@OptIn(ExperimentalMultiplatform::class)
@OptionalExpectation
public expect annotation class JvmSynthetic()
