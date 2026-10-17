/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from Kotlin 2.3.10 commonMain/kotlin/JvmAnnotationsH.kt.
 */
package kotlin.jvm

@Target(AnnotationTarget.FIELD)
@MustBeDocumented
@OptIn(ExperimentalMultiplatform::class)
@OptionalExpectation
public expect annotation class JvmField()
