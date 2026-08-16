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
 * When you apply the [ConsistentCopyVisibility] annotation to a data class with non-public constructor:
 * 1. The generated 'copy' method will have the same visibility as the primary constructor.
 *    You enroll into the new behavior right away.
 * 2. You disable all the warnings/errors about the behavior change because they become unnecessary.
 *
 * The effect of '-Xconsistent-data-class-copy-visibility' flag is the same as applying [ConsistentCopyVisibility] to all data classes in the module.
 *
 * @see [kotlin.annotations.ConsistentCopyVisibility]
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
@SinceKotlin("2.0")
public annotation class ConsistentCopyVisibility
