package kotlinx.coroutines.debug

import java.lang.StackTraceElement
import java.lang.System
import kotlin.collections.ArrayList
import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName
import kotlinx.coroutines.Job

@KsSymbolName("kk_debug_probes_install")
private external fun __debugProbesInstall(): Int

@KsSymbolName("kk_debug_probes_uninstall")
private external fun __debugProbesUninstall(): Int

@KsSymbolName("kk_debug_probes_is_installed")
private external fun __debugProbesIsInstalled(): Int

@KsSymbolName("kk_debug_probes_get_creation_stack_traces")
private external fun __debugProbesGetCreationStackTraces(): Int

@KsSymbolName("kk_debug_probes_set_creation_stack_traces")
private external fun __debugProbesSetCreationStackTraces(enabled: Int): Int

@KsSymbolName("kk_debug_probes_get_sanitize_stack_traces")
private external fun __debugProbesGetSanitizeStackTraces(): Int

@KsSymbolName("kk_debug_probes_set_sanitize_stack_traces")
private external fun __debugProbesSetSanitizeStackTraces(enabled: Int): Int

@KsSymbolName("kk_debug_probes_snapshot_create")
private external fun __debugProbesSnapshotCreate(): Int

@KsSymbolName("kk_debug_probes_snapshot_count")
private external fun __debugProbesSnapshotCount(snapshot: Int): Int

@KsSymbolName("kk_debug_probes_snapshot_state")
private external fun __debugProbesSnapshotState(snapshot: Int, index: Int): Int

@KsSymbolName("kk_debug_probes_snapshot_context")
private external fun __debugProbesSnapshotContext(snapshot: Int, index: Int): CoroutineContext

@KsSymbolName("kk_debug_probes_snapshot_creation_trace_count")
private external fun __debugProbesSnapshotCreationTraceCount(snapshot: Int, index: Int): Int

@KsSymbolName("kk_debug_probes_snapshot_creation_trace_at")
private external fun __debugProbesSnapshotCreationTraceAt(snapshot: Int, index: Int, frameIndex: Int): String?

@KsSymbolName("kk_debug_probes_snapshot_release")
private external fun __debugProbesSnapshotRelease(snapshot: Int): Int

public object DebugProbes {
    public var enableCreationStackTraces: Boolean
        get() = __debugProbesGetCreationStackTraces() != 0
        set(value) {
            __debugProbesSetCreationStackTraces(if (value) 1 else 0)
        }

    public var sanitizeStackTraces: Boolean
        get() = __debugProbesGetSanitizeStackTraces() != 0
        set(value) {
            __debugProbesSetSanitizeStackTraces(if (value) 1 else 0)
        }

    public val isInstalled: Boolean
        get() = __debugProbesIsInstalled() != 0

    public fun install() {
        __debugProbesInstall()
    }

    public fun uninstall() {
        __debugProbesUninstall()
    }

    public fun dumpCoroutines() {
        val coroutines = dumpCoroutinesInfo()
        System.err.println("Coroutines dump (${coroutines.size})")
        var index = 0
        while (index < coroutines.size) {
            val info = coroutines[index]
            System.err.println("Coroutine #${index + 1}: state=${info.state}, context=${info.context}")
            for (frame in info.creationStackTrace) {
                System.err.println("\tat $frame")
            }
            index += 1
        }
    }

    public fun dumpCoroutinesInfo(): List<CoroutineInfo> {
        if (!isInstalled) {
            throw IllegalStateException("Debug probes are not installed")
        }
        val snapshot = __debugProbesSnapshotCreate()
        try {
            val count = __debugProbesSnapshotCount(snapshot)
            val result = ArrayList<CoroutineInfo>(count)
            var index = 0
            while (index < count) {
                val state = when (__debugProbesSnapshotState(snapshot, index)) {
                    0 -> State.CREATED
                    1 -> State.RUNNING
                    2 -> State.SUSPENDED
                    else -> State.CANCELLED
                }
                val traceCount = __debugProbesSnapshotCreationTraceCount(snapshot, index)
                val creationStackTrace = ArrayList<StackTraceElement>(traceCount)
                var frameIndex = 0
                while (frameIndex < traceCount) {
                    val frame = __debugProbesSnapshotCreationTraceAt(snapshot, index, frameIndex)
                    if (frame != null) {
                        creationStackTrace.add(StackTraceElement("", "", null, -1, frame.removePrefix("\tat ")))
                    }
                    frameIndex += 1
                }
                result.add(
                    CoroutineInfo(
                        context = __debugProbesSnapshotContext(snapshot, index),
                        state = state,
                        creationStackTrace = creationStackTrace
                    )
                )
                index += 1
            }
            return result
        } finally {
            __debugProbesSnapshotRelease(snapshot)
        }
    }

    public fun <T> withDebugProbes(block: () -> T): T {
        install()
        try {
            return block()
        } finally {
            uninstall()
        }
    }
}

public enum class State {
    CREATED,
    RUNNING,
    SUSPENDED,
    CANCELLED
}

public class CoroutineInfo internal constructor(
    public val context: CoroutineContext,
    public val state: State,
    public val creationStackTrace: List<StackTraceElement>
) {
    public val job: Job?
        get() = context[Job]

    public fun lastObservedStackTrace(): List<StackTraceElement> = emptyList()

    public override fun toString(): String = "CoroutineInfo(state=$state,context=$context)"
}
