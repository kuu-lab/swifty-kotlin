/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/annotations/ConsistentCopyVisibility.kt>.
 */

package kotlin

/**
 * In previous versions of Kotlin, the generated 'copy' method of a data class always had public visibility,
 * even if the primary constructor was non-public. That exposed the non-public constructor of the data class.
 *
 * In future versions of Kotlin,
 * the generated 'copy' method of a data class will have the same visibility as the primary constructor.
 *
 * When you apply [ExposedCopyVisibility] annotation to your data class:
 * 1. You choose to keep the public **binary** visibility of the generated 'copy' method.
 *    But illegal usages of the 'copy' method will become inaccessible anyway.
 * 2. You suppress the warning/error about the behavior change only on the declaration.
 *    **Please note** that the warning/error on all the illegal **usages** of the 'copy' method **stays even if you use [ExposedCopyVisibility]!**
 *
 * @see [ConsistentCopyVisibility]
 * @see [KT-11914](https://youtrack.jetbrains.com/issue/KT-11914)
 */
@kotlin.annotation.Target(AnnotationTarget.CLASS)
@kotlin.annotation.Retention(AnnotationRetention.SOURCE)
@SinceKotlin("2.0")
public annotation class ExposedCopyVisibility
