/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotation/OverloadResolutionByLambdaReturnType.kt>.
 */
package kotlin

@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.SinceKotlin("1.4")
@kotlin.experimental.ExperimentalTypeInference
public annotation class OverloadResolutionByLambdaReturnType
