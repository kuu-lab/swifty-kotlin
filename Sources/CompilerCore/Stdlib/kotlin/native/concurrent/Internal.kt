/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/Internal.kt>.
 */

package kotlin.native.concurrent

import kotlin.native.internal.ExportForCompiler
import kotlin.native.internal.InternalForKotlinNative
import kotlin.native.internal.NativePtr
import kotlin.native.internal.__nativeConcurrentAttachObjectGraph
import kotlin.native.internal.__nativeConcurrentConsumeFuture
import kotlin.native.internal.__nativeConcurrentDetachObjectGraph
import kotlin.native.internal.__nativeConcurrentExecuteImpl
import kotlin.native.internal.__nativeConcurrentWaitWorkerTermination
import kotlinx.cinterop.CFunction
import kotlinx.cinterop.CPointer

@PublishedApi
@ObsoleteWorkersApi
internal fun attachObjectGraphInternal(stable: NativePtr): Any? =
    __nativeConcurrentAttachObjectGraph(stable)

@PublishedApi
@ObsoleteWorkersApi
internal fun consumeFuture(id: Int): Any? = __nativeConcurrentConsumeFuture(id)

@PublishedApi
@ObsoleteWorkersApi
internal fun detachObjectGraphInternal(mode: Int, producer: () -> Any?): NativePtr =
    __nativeConcurrentDetachObjectGraph(mode, producer())

@PublishedApi
@ExportForCompiler
@ObsoleteWorkersApi
internal fun executeImpl(
    worker: Worker,
    mode: TransferMode,
    producer: () -> Any?,
    job: CPointer<CFunction<*>>
): Future<Any?> = __nativeConcurrentExecuteImpl(worker, mode, producer(), job)

@InternalForKotlinNative
@ObsoleteWorkersApi
public fun waitWorkerTermination(worker: Worker): Unit =
    __nativeConcurrentWaitWorkerTermination(worker)
