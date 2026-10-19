/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-test <libraries/kotlin.test/annotations-common/src/main/kotlin/kotlin.test/Annotations.kt>
 * and <kotlin-native/runtime/src/main/kotlin/kotlin/test/Annotation.kt> (Kotlin 2.3.10).
 */

package kotlin.test

@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
public annotation class Test

@kotlin.annotation.Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
public annotation class Ignore

@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
public annotation class BeforeTest

@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
public annotation class AfterTest

/** Kotlin/Native lifecycle. */
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
public annotation class BeforeClass

/** Kotlin/Native lifecycle. */
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
public annotation class AfterClass
