package golden.sema

import kotlin.native.runtime.Debugging

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun debuggingSurface(): Boolean {
    val runnable: Boolean = Debugging.isThreadStateRunnable
    Debugging.forceCheckedShutdown = !Debugging.forceCheckedShutdown
    val dumped: Boolean = Debugging.dumpMemory(2L)
    return runnable && dumped
}
