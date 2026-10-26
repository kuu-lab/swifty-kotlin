package java.lang

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_process_current_pid")
private external fun __currentProcessPid(): kotlin.Long

public class ProcessHandle private constructor(private val processId: kotlin.Long) {
    public fun pid(): kotlin.Long = processId

    public fun isAlive(): kotlin.Boolean = processId == __currentProcessPid()

    public companion object {
        public fun current(): ProcessHandle = ProcessHandle(__currentProcessPid())
    }
}
