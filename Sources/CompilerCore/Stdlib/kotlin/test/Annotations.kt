/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-test <libraries/kotlin.test/annotations-common/src/main/kotlin/kotlin.test/Annotations.kt>
 * and <kotlin-native/runtime/src/main/kotlin/kotlin/test/Annotation.kt> (Kotlin 2.3.10).
 */

package kotlin.test

/** Marks a class member function with no parameters and a Unit return type as a test. */
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
public annotation class Test

/** Marks a test or a suite as ignored. */
@kotlin.annotation.Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
public annotation class Ignore

/** Marks a class member function to be invoked before each test. */
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
public annotation class BeforeTest

/** Marks a class member function to be invoked after each test. */
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
public annotation class AfterTest
