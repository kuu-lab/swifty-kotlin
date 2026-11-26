package java.lang

import java.time.Duration
import java.time.Instant
import java.util.Optional
import java.util.concurrent.CompletableFuture
import java.util.stream.Stream
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_process_current_pid")
private external fun __currentProcessPid(): kotlin.Long

@KsSymbolName("__kk_process_handle_alive")
private external fun __processHandleAlive(pid: kotlin.Long): Int

@KsSymbolName("__kk_process_handle_destroy")
private external fun __processHandleDestroy(pid: kotlin.Long, forcible: kotlin.Int): Int

@KsSymbolName("__kk_process_handle_table")
private external fun __processHandleTable(): List<kotlin.Long>

@KsSymbolName("__kk_process_info_command")
private external fun __processInfoCommand(pid: kotlin.Long): String?

@KsSymbolName("__kk_process_info_command_line")
private external fun __processInfoCommandLine(pid: kotlin.Long): String?

@KsSymbolName("__kk_process_info_arguments")
private external fun __processInfoArguments(pid: kotlin.Long): Array<String>?

@KsSymbolName("__kk_process_info_start_time")
private external fun __processInfoStartTime(pid: kotlin.Long): kotlin.Long

@KsSymbolName("__kk_process_info_cpu_time")
private external fun __processInfoCpuTime(pid: kotlin.Long): kotlin.Long

@KsSymbolName("__kk_process_info_user")
private external fun __processInfoUser(pid: kotlin.Long): String?

/**
 * A handle to a native process, mirroring `java.lang.ProcessHandle`.
 *
 * Deviations from the JDK:
 * - Handles compare equal by PID only; the JDK additionally compares the
 *   process start time to guard against PID reuse.
 * - [ProcessHandle.Info] fields are populated from OS process tables; fields
 *   the platform cannot provide are returned as empty [Optional]s.
 */
public interface ProcessHandle : Comparable<ProcessHandle> {
    public fun pid(): kotlin.Long

    public fun info(): Info

    public fun onExit(): CompletableFuture<ProcessHandle>

    public fun supportsNormalTermination(): kotlin.Boolean

    public fun destroy(): kotlin.Boolean

    public fun destroyForcibly(): kotlin.Boolean

    public fun isAlive(): kotlin.Boolean

    public fun children(): Stream<ProcessHandle>

    public fun descendants(): Stream<ProcessHandle>

    public fun parent(): Optional<ProcessHandle>

    public interface Info {
        public fun command(): Optional<String>

        public fun commandLine(): Optional<String>

        public fun arguments(): Optional<Array<String>>

        public fun startInstant(): Optional<Instant>

        public fun totalCpuDuration(): Optional<Duration>

        public fun user(): Optional<String>
    }

    public companion object {
        private val currentHandle: ProcessHandle = ProcessHandleImpl(__currentProcessPid())

        public fun of(pid: kotlin.Long): Optional<ProcessHandle> =
            if (__processHandleAlive(pid) != 0) {
                Optional.of(ProcessHandleImpl(pid))
            } else {
                Optional.empty()
            }

        public fun current(): ProcessHandle = currentHandle

        public fun allProcesses(): Stream<ProcessHandle> {
            val table = __processHandleTable()
            val handles = mutableListOf<ProcessHandle>()
            var index = 0
            while (index < table.size) {
                handles.add(ProcessHandleImpl(table[index]))
                index += 2
            }
            return Stream.of(*handles.toTypedArray())
        }
    }
}

internal class ProcessHandleImpl internal constructor(
    private val processId: kotlin.Long,
) : ProcessHandle {
    override fun pid(): kotlin.Long = processId

    override fun info(): ProcessHandle.Info = ProcessHandleInfoSnapshot(
        command = __processInfoCommand(processId),
        commandLine = __processInfoCommandLine(processId),
        arguments = __processInfoArguments(processId),
        startEpochMillis = __processInfoStartTime(processId),
        cpuNanos = __processInfoCpuTime(processId),
        user = __processInfoUser(processId),
    )

    override fun onExit(): CompletableFuture<ProcessHandle> {
        if (processId == __currentProcessPid()) {
            throw IllegalStateException("onExit for current process not allowed")
        }
        val future = CompletableFuture<ProcessHandle>()
        if (!isAlive()) {
            future.complete(this)
            return future
        }
        Thread {
            while (isAlive()) Thread.sleep(10)
            future.complete(this)
        }.apply {
            isDaemon = true
            start()
        }
        return future
    }

    override fun supportsNormalTermination(): kotlin.Boolean = true

    override fun destroy(): kotlin.Boolean {
        checkNotCurrentProcess()
        return __processHandleDestroy(processId, 0) != 0
    }

    override fun destroyForcibly(): kotlin.Boolean {
        checkNotCurrentProcess()
        return __processHandleDestroy(processId, 1) != 0
    }

    override fun isAlive(): kotlin.Boolean = __processHandleAlive(processId) != 0

    override fun children(): Stream<ProcessHandle> {
        val table = __processHandleTable()
        val handles = mutableListOf<ProcessHandle>()
        var index = 0
        while (index + 1 < table.size) {
            if (table[index + 1] == processId && table[index] != processId) {
                handles.add(ProcessHandleImpl(table[index]))
            }
            index += 2
        }
        return Stream.of(*handles.toTypedArray())
    }

    override fun descendants(): Stream<ProcessHandle> {
        val table = __processHandleTable()
        val childrenOf = mutableMapOf<kotlin.Long, MutableList<kotlin.Long>>()
        var index = 0
        while (index + 1 < table.size) {
            val pid = table[index]
            val ppid = table[index + 1]
            childrenOf.getOrPut(ppid) { mutableListOf() }.add(pid)
            index += 2
        }
        val result = mutableListOf<ProcessHandle>()
        val visited = mutableSetOf(processId)
        val queue = mutableListOf(processId)
        var head = 0
        while (head < queue.size) {
            val parent = queue[head]
            head += 1
            val kids = childrenOf[parent] ?: continue
            for (kid in kids) {
                if (visited.add(kid)) {
                    result.add(ProcessHandleImpl(kid))
                    queue.add(kid)
                }
            }
        }
        return Stream.of(*result.toTypedArray())
    }

    override fun parent(): Optional<ProcessHandle> {
        val table = __processHandleTable()
        var index = 0
        while (index + 1 < table.size) {
            if (table[index] == processId) {
                val ppid = table[index + 1]
                return if (ppid > 0L) {
                    Optional.of(ProcessHandleImpl(ppid))
                } else {
                    Optional.empty()
                }
            }
            index += 2
        }
        return Optional.empty()
    }

    override fun compareTo(other: ProcessHandle): Int = processId.compareTo(other.pid())

    override fun equals(other: Any?): kotlin.Boolean =
        other is ProcessHandle && other.pid() == processId

    override fun hashCode(): Int = processId.hashCode()

    override fun toString(): String = processId.toString()

    private fun checkNotCurrentProcess() {
        if (processId == __currentProcessPid()) {
            throw IllegalStateException("destroy of current process not allowed")
        }
    }
}

private class ProcessHandleInfoSnapshot(
    private val command: String?,
    private val commandLine: String?,
    private val arguments: Array<String>?,
    private val startEpochMillis: kotlin.Long,
    private val cpuNanos: kotlin.Long,
    private val user: String?,
) : ProcessHandle.Info {
    override fun command(): Optional<String> = Optional.ofNullable(command)

    override fun commandLine(): Optional<String> = Optional.ofNullable(commandLine)

    override fun arguments(): Optional<Array<String>> = Optional.ofNullable(arguments)

    override fun startInstant(): Optional<Instant> =
        if (startEpochMillis > 0L) {
            Optional.of(Instant.ofEpochMilli(startEpochMillis))
        } else {
            Optional.empty()
        }

    override fun totalCpuDuration(): Optional<Duration> =
        if (cpuNanos >= 0L) {
            Optional.of(Duration.ofNanos(cpuNanos))
        } else {
            Optional.empty()
        }

    override fun user(): Optional<String> = Optional.ofNullable(user)
}
