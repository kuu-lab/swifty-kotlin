/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/ref/Cleaner.kt>.
 *
 * KSP-1254: the cleaner handle is runtime-owned, so the public factory keeps a
 * private bridge instead of a synthetic member stub.
 */

package kotlin.native.ref

import kotlin.experimental.ExperimentalNativeApi
import kotlin.internal.KsSymbolName
import kotlin.native.internal.ExportForCompiler

@ExperimentalNativeApi
@SinceKotlin("1.9")
public sealed interface Cleaner

@ExperimentalNativeApi
@KsSymbolName("kk_cleaner_create")
private external fun createCleanerBridge(
    resource: Any?,
    cleanupAction: Any?
): Cleaner

@ExperimentalNativeApi
@SinceKotlin("1.9")
@ExportForCompiler
public fun <T> createCleaner(
    resource: T,
    cleanupAction: (resource: T) -> Unit
): Cleaner = createCleanerBridge(resource, cleanupAction)
