/*
 * Copyright 2010-2021 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 * Derived from Kotlin 2.3.10 commonMain/kotlin/JvmAnnotationsH.kt.
 */
package kotlin.jvm

@Target(AnnotationTarget.FILE, AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.PROPERTY_SETTER)
@MustBeDocumented
@OptIn(ExperimentalMultiplatform::class)
@OptionalExpectation
public expect annotation class JvmName(val name: String)
