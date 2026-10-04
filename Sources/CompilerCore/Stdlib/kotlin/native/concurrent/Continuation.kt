/*
 * Copyright 2010-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license
 * that can be found in the LICENSE file.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Continuation.kt.
 * Only the top-level callContinuation0/1/2 functions are migrated here (KSP-1217);
 * Continuation0/1/2 remain the synthetic stubs registered by
 * HeaderHelpers+SyntheticNativeConcurrentRegistry.swift.
 */
@file:OptIn(ExperimentalForeignApi::class)

package kotlin.native.concurrent

import kotlinx.cinterop.COpaquePointer
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.StableRef
import kotlinx.cinterop.asStableRef

// KSWIFTK: a `private const val` reference isn't evaluated when rendering the
// @Deprecated diagnostic message (it prints the identifier, not its value), so
// the message is inlined at each use instead of factored into a shared const
// the way upstream's DEPRECATED_API_MESSAGE does.

@Deprecated("This API is deprecated without replacement", level = DeprecationLevel.WARNING)
public fun COpaquePointer.callContinuation0() {
    val single = this.asStableRef<() -> Unit>()
    single.get()()
}

@Deprecated("This API is deprecated without replacement", level = DeprecationLevel.WARNING)
public fun <T1> COpaquePointer.callContinuation1() {
    val pair = this.asStableRef<Pair<StableRef<(T1) -> Unit>, T1>>().get()
    pair.first.get()(pair.second)
}

@Deprecated("This API is deprecated without replacement", level = DeprecationLevel.WARNING)
public fun <T1, T2> COpaquePointer.callContinuation2() {
    val triple = this.asStableRef<Triple<StableRef<(T1, T2) -> Unit>, T1, T2>>().get()
    triple.first.get()(triple.second, triple.third)
}
