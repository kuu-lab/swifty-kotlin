/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Freezing.kt>.
 */

package kotlin.native.concurrent

import kotlin.internal.KsSymbolName

@kotlin.experimental.ExperimentalNativeApi
public class InvalidMutabilityException : RuntimeException {
    @KsSymbolName("__kk_invalid_mutability_exception_new_message")
    public constructor(message: String)
}
