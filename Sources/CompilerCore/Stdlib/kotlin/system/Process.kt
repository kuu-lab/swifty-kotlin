package kotlin.system

import kotlin.internal.KsSymbolName

// Migration source: Sources/Runtime/RuntimeSystem.swift (now the demoted
// __kk_system_exitProcess OS bridge).

@KsSymbolName("__kk_system_exitProcess")
private external fun __kkSystemExitProcess(status: Int): Nothing

public fun exitProcess(status: Int): Nothing = __kkSystemExitProcess(status)
