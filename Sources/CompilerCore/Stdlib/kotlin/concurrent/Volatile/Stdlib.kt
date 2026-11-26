/*
 * Copyright 2010-2022 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/Volatile.kt>
 * and the Kotlin/Native actual declaration.
 */

package kotlin.concurrent

@Target(AnnotationTarget.FIELD)
@Retention(AnnotationRetention.SOURCE)
@MustBeDocumented
@SinceKotlin("1.9")
@WasExperimental(ExperimentalStdlibApi::class)
public annotation class Volatile()
