package golden.sema

import kotlin.native.internal.NativePtr
import kotlin.concurrent.AtomicNativePtr

fun construct(value: NativePtr): AtomicNativePtr = AtomicNativePtr(value)
