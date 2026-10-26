package java.lang

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_process_wait_for")
private external fun __waitForProcess(handle: kotlin.Long): Int

@KsSymbolName("__kk_process_exit_value")
private external fun __processExitValue(handle: kotlin.Long): Int

@KsSymbolName("__kk_process_is_alive")
private external fun __isProcessAlive(handle: kotlin.Long): Int

@KsSymbolName("__kk_process_pid")
private external fun __processPid(handle: kotlin.Long): kotlin.Long

@KsSymbolName("__kk_process_destroy")
private external fun __destroyProcess(handle: kotlin.Long)

public open class Process internal constructor(private val handle: kotlin.Long) {
    public val isAlive: kotlin.Boolean
        get() = __isProcessAlive(handle) != 0

    public fun pid(): kotlin.Long = __processPid(handle)

    public fun waitFor(): Int = __waitForProcess(handle)

    public fun exitValue(): Int {
        val value = __processExitValue(handle)
        if (value == Int.MIN_VALUE) throw IllegalThreadStateException("Process has not exited")
        return value
    }

    public fun destroy() {
        __destroyProcess(handle)
    }

    public fun destroyForcibly(): Process {
        destroy()
        return this
    }
}
