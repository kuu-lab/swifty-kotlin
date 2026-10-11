/*
 * Derived from kotlinx-atomicfu 0.33.0 (fc175fc575419ca9eae0d3c14cefe9c5cd7ca351).
 * Copyright JetBrains s.r.o. Licensed under the Apache License, Version 2.0.
 */
@file:OptIn(ExperimentalThreadBlockingApi::class)
package kotlinx.atomicfu.locks

import kotlin.internal.KsSymbolName
import kotlin.time.Duration
import kotlin.time.TimeMark

@KsSymbolName("__kk_atomicfu_parker_new")
private external fun newAtomicfuParkerKernel(): Any
@KsSymbolName("__kk_atomicfu_parker_wait")
private external fun atomicfuPark(kernel: Any, timeoutNanos: Long): Unit
@KsSymbolName("__kk_atomicfu_parker_unpark")
private external fun atomicfuUnpark(kernel: Any): Unit
@KsSymbolName("__kk_atomicfu_current_parking_handle")
private external fun atomicfuCurrentParkingHandle(factory: () -> ParkingHandle): ParkingHandle

@ExperimentalThreadBlockingApi
public class ParkingHandle internal constructor() {
    // This object reference is traced by GC. A raw Long address would not keep
    // the managed kernel alive when the wrapper outlives its originating thread.
    internal val kernel: Any = newAtomicfuParkerKernel()
}

@ExperimentalThreadBlockingApi
public object ParkingSupport {
    public fun park(timeout: Duration): Unit =
        atomicfuPark(currentThreadHandle().kernel, timeout.atomicfuTimeoutNanos())
    public fun parkUntil(deadline: TimeMark): Unit = park(deadline.elapsedNow() * -1)
    public fun unpark(handle: ParkingHandle): Unit = atomicfuUnpark(handle.kernel)
    public fun currentThreadHandle(): ParkingHandle = atomicfuCurrentParkingHandle { ParkingHandle() }
}

@Retention(AnnotationRetention.BINARY)
@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.TYPEALIAS,
)
@RequiresOptIn(
    level = RequiresOptIn.Level.ERROR,
    message = "This API is experimental. It is low-level and might change in the future."
)
public annotation class ExperimentalThreadBlockingApi
