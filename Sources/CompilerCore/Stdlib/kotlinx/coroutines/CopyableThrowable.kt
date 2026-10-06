/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 * Derived from kotlinx-coroutines-core/common/src/Debug.common.kt.
 */
package kotlinx.coroutines

/** A throwable that can provide a copy for stacktrace recovery, or opt out by returning null. */
@ExperimentalCoroutinesApi
public interface CopyableThrowable<T> where T : Throwable, T : CopyableThrowable<T> {
    public fun createCopy(): T?
}
