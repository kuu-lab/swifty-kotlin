/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/Enum.kt.
 */

@file:Suppress("KSWIFTK-SEMA-ABSTRACT")

package kotlin

// KSP-732: nominal `kotlin.Enum<T : Enum<T>>` declaration migrated out of the
// synthetic self-registration. The actual `name` / `ordinal` accessors and
// `compareTo` are compiler residuals handled elsewhere; this source shell
// provides the public type declaration for `is` checks and generic bounds.
public abstract class Enum<T : Enum<T>> protected constructor(
    name: String,
    ordinal: Int
) : Comparable<T> {
    public companion object {}
}

// KSP-776: These declarations are the source-backed public surface for the
// reified enum intrinsics. Their fallback bodies are never executed for a
// concrete enum call: CallTypeChecker records the intrinsic binding and
// CallLowerer expands it using the enum class's generated members.
public inline fun <reified T : Enum<T>> enumValues(): Array<T> =
    throw IllegalStateException("enumValues is expanded by the compiler")

public inline fun <reified T : Enum<T>> enumValueOf(name: String): T =
    throw IllegalStateException("enumValueOf is expanded by the compiler")
