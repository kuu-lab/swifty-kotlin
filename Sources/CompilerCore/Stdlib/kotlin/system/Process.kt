package kotlin.system

import kotlin.internal.KsSymbolName

// KSP-617
// Public kotlin.system.exitProcess layer migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeSystem.swift (kk_system_exitProcess),
// now the demoted __kk_system_exitProcess OS bridge.

@KsSymbolName("__kk_system_exitProcess")
private external fun __kkSystemExitProcess(status: Int): Nothing

public fun exitProcess(status: Int): Nothing = __kkSystemExitProcess(status)
