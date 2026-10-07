package kotlinx.coroutines.debug

public object DebugProbes {
    public var enableCreationStackTraces: Boolean = false
    public var sanitizeStackTraces: Boolean = true
    public val isInstalled: Boolean get() = false

    public fun install() {}
    public fun uninstall() {}
    public fun dumpCoroutines() {}
    public fun dumpCoroutinesInfo(): List<CoroutineInfo> = emptyList()
    public fun <T> withDebugProbes(block: () -> T): T = block()
}

public class CoroutineInfo
