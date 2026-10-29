package kotlin.concurrent

import java.lang.ClassLoader
import java.lang.Runnable
import java.lang.Thread

public fun thread(
    start: Boolean = true,
    isDaemon: Boolean = false,
    contextClassLoader: ClassLoader? = null,
    name: String? = null,
    priority: Int = -1,
    block: () -> Unit
): Thread {
    val result = Thread(Runnable { block() })
    if (isDaemon) result.isDaemon = true
    if (priority > 0) result.priority = priority
    if (name != null) result.name = name
    if (contextClassLoader != null) result.contextClassLoader = contextClassLoader
    if (start) result.start()
    return result
}
