package kotlin.concurrent

import java.lang.ThreadLocal

public inline fun <T> ThreadLocal<T>.getOrSet(default: () -> T): T {
    val value = get()
    if (value != null) return value
    val newValue = default()
    __storeValue(newValue)
    return newValue
}
