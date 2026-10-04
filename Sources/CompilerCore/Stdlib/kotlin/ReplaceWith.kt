/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/Annotations.kt>.
 */

package kotlin

@kotlin.annotation.Target()
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
public annotation class ReplaceWith(val expression: String, vararg val imports: String)
