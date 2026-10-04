// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

import kotlin.native.internal.NativePtr
import kotlin.concurrent.AtomicNativePtr

fun construct(value: NativePtr): AtomicNativePtr = AtomicNativePtr(value)
