package java.lang

import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_process_wait_for")
private external fun __waitForProcess(handle: kotlin.Long): Int

@KsSymbolName("__kk_process_wait_for_timeout")
private external fun __waitForProcessTimeout(handle: kotlin.Long, timeoutNanos: kotlin.Long): Int

@KsSymbolName("__kk_process_exit_value")
private external fun __processExitValue(handle: kotlin.Long): Int

@KsSymbolName("__kk_process_is_alive")
private external fun __isProcessAlive(handle: kotlin.Long): Int

@KsSymbolName("__kk_process_pid")
private external fun __processPid(handle: kotlin.Long): kotlin.Long

@KsSymbolName("__kk_process_destroy")
private external fun __destroyProcess(handle: kotlin.Long)

@KsSymbolName("__kk_process_destroy_forcibly")
private external fun __destroyProcessForcibly(handle: kotlin.Long)

@KsSymbolName("__kk_process_input_stream")
private external fun __processInputStream(handle: kotlin.Long): InputStream

@KsSymbolName("__kk_process_output_stream")
private external fun __processOutputStream(handle: kotlin.Long): OutputStream

@KsSymbolName("__kk_process_error_stream")
private external fun __processErrorStream(handle: kotlin.Long): InputStream

public open class Process internal constructor(private val handle: kotlin.Long) {
    public val isAlive: kotlin.Boolean
        get() = __isProcessAlive(handle) != 0

    public fun pid(): kotlin.Long = __processPid(handle)

    public fun waitFor(): Int = __waitForProcess(handle)

    public fun waitFor(timeout: kotlin.Long, unit: TimeUnit): kotlin.Boolean =
        __waitForProcessTimeout(handle, unit.toNanos(timeout)) != 0

    public fun exitValue(): Int {
        val value = __processExitValue(handle)
        if (value == Int.MIN_VALUE) throw IllegalThreadStateException("Process has not exited")
        return value
    }

    public fun destroy() {
        __destroyProcess(handle)
    }

    public fun destroyForcibly(): Process {
        __destroyProcessForcibly(handle)
        return this
    }

    public fun supportsNormalTermination(): kotlin.Boolean = true

    public fun onExit(): CompletableFuture<Process> {
        if (!isAlive) return CompletableFuture.completedFuture(this)
        val future = CompletableFuture<Process>()
        Thread {
            waitFor()
            future.complete(this)
        }.apply {
            isDaemon = true
            start()
        }
        return future
    }

    public fun toHandle(): ProcessHandle = ProcessHandleImpl(pid())

    public val inputStream: InputStream get() = getInputStream()

    public val outputStream: OutputStream get() = getOutputStream()

    public val errorStream: InputStream get() = getErrorStream()

    public fun getInputStream(): InputStream = __processInputStream(handle)

    public fun getOutputStream(): OutputStream = __processOutputStream(handle)

    public fun getErrorStream(): InputStream = __processErrorStream(handle)

    override fun toString(): String {
        val exit = if (isAlive) "\"not exited\"" else exitValue().toString()
        return "Process[pid=${pid()}, exitValue=$exit]"
    }
}
