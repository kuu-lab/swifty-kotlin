/*
 * Copyright 2010-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license
 * that can be found in the LICENSE file.
 *
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/native/concurrent/WorkerBoundReference.kt.
 */

package kotlin.native.concurrent

import kotlin.native.internal.__nativeConcurrentCurrentWorker

@ObsoleteWorkersApi
@Deprecated("Support for the legacy memory manager has been completely removed. Use the referenced value directly.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class WorkerBoundReference<out T : Any>(
    public val value: T
) {
    public val valueOrNull: T?
        get() = value

    public val worker: Worker = __nativeConcurrentCurrentWorker()
}
