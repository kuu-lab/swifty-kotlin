@file:kotlin.jvm.JvmName("StandardKt")
package kotlin

import kotlin.jvm.internal.__jvmMonitorEnter
import kotlin.jvm.internal.__jvmMonitorExit

public inline fun <R> synchronized(lock: Any, block: () -> R): R {
    __jvmMonitorEnter(lock)
    try {
        return block()
    } finally {
        __jvmMonitorExit(lock)
    }
}
