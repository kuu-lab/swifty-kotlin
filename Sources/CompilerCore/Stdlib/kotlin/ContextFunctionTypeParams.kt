/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/Annotations.kt>.
 */

package kotlin

/**
 * This annotation is used to denote a function type with context receivers.
 * The parameter [count] specifies the number of context receivers in the function type.
 */
@kotlin.annotation.Target(AnnotationTarget.TYPE)
@kotlin.annotation.MustBeDocumented
@kotlin.SinceKotlin("1.7")
public annotation class ContextFunctionTypeParams(val count: Int)
