/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/IgnorableReturnValue.kt>.
 */

package kotlin

/**
 * Instructs the Kotlin compiler to allow the return value of the annotated function to be ignored.
 */
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class IgnorableReturnValue
