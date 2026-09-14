/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/runtime/Debugging.kt>.
 *
 * KSP-1260: source-back the full `Debugging` member surface. The runtime owns
 * thread-state and shutdown-mode tracking, so each member keeps a private
 * top-level bridge instead of a synthetic member stub.
 */

package kotlin.native.runtime

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_debugging_is_thread_state_runnable")
private external fun __debuggingIsThreadStateRunnable(): Int

@KsSymbolName("__kk_debugging_force_checked_shutdown_get")
private external fun __debuggingGetForceCheckedShutdown(): Int

@KsSymbolName("__kk_debugging_force_checked_shutdown_set")
private external fun __debuggingSetForceCheckedShutdown(value: Int): Unit

@KsSymbolName("__kk_debugging_dump_memory")
private external fun __debuggingDumpMemory(fd: Long): Int

/**
 * Namespace for various debugging-related functionality provided by the
 * Kotlin/Native runtime.
 */
@NativeRuntimeApi
@SinceKotlin("1.9")
public object Debugging {
    /** `true` if the current thread state is runnable, `false` if it's native. */
    public val isThreadStateRunnable: Boolean
        get() = __debuggingIsThreadStateRunnable() != 0

    /**
     * When set to `true`, forces the runtime to run its full checked shutdown
     * sequence even in contexts that would otherwise skip it.
     */
    public var forceCheckedShutdown: Boolean
        get() = __debuggingGetForceCheckedShutdown() != 0
        set(value) {
            __debuggingSetForceCheckedShutdown(if (value) 1 else 0)
        }

    /**
     * Dumps a snapshot of the current native heap allocations into [fd].
     * Returns `true` on success.
     */
    public fun dumpMemory(fd: Long): Boolean = __debuggingDumpMemory(fd) != 0
}
