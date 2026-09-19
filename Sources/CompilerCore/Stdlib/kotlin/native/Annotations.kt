/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/Annotations.kt>.
 */

package kotlin.native

/**
 * Internal opt-in marker used by Kotlin/Native's dangerous SymbolName API.
 */
@kotlin.RequiresOptIn(
    message = "@SymbolName is dangerous deprecated and internal annotation. See https://youtrack.jetbrains.com/issue/KT-46649",
    level = kotlin.RequiresOptIn.Level.ERROR
)
@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
internal annotation class SymbolNameIsInternal

/**
 * Assigns a native symbol name to a top-level function.
 */
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@SymbolNameIsInternal
public annotation class SymbolName(val name: String)

@kotlin.annotation.Target(AnnotationTarget.PROPERTY)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.ExperimentalStdlibApi
@kotlin.Deprecated(
    message = "This annotation is a temporal migration assistance and may be removed in the future releases, please consider filing an issue about the case where it is needed"
)
public annotation class EagerInitialization

@kotlin.annotation.Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.experimental.ExperimentalNativeApi
public annotation class NoInline

@kotlin.annotation.Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.CLASS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class CName(
    val externName: String = "",
    val shortName: String = ""
)

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.VALUE_PARAMETER,
    AnnotationTarget.FUNCTION
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
@kotlin.experimental.ExperimentalObjCName
@kotlin.SinceKotlin("1.8")
public annotation class ObjCName(
    val name: String = "",
    val swiftName: String = "",
    val exact: Boolean = false
)

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class HidesFromObjC

@kotlin.annotation.Target(
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.CLASS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.native.HidesFromObjC
@kotlin.experimental.ExperimentalObjCRefinement
public annotation class HiddenFromObjC

@kotlin.annotation.Target(AnnotationTarget.ANNOTATION_CLASS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class RefinesInSwift

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ShouldRefineInSwift

// KSP-1541: upstream declares this under `kotlinx.cinterop`
// (kotlin-native/Interop/Runtime/src/main/kotlin/kotlinx/cinterop/Annotations.kt).
// Kept in `kotlin.native` here since KSwiftK has no separate cinterop runtime
// package; moving it would change its fully-qualified name.
@kotlin.annotation.Target(AnnotationTarget.FUNCTION)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class ObjCSignatureOverride
