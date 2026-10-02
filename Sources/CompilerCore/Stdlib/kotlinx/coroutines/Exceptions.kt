/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core/common/src/Exceptions.common.kt.
 */
package kotlinx.coroutines

public typealias CancellationException = kotlin.coroutines.cancellation.CancellationException

/** A job was cancelled before completing normally. */
internal class JobCancellationException(
    message: String,
    cause: Throwable?,
    val job: Job
) : CancellationException(message, cause)

/** The deadline of a withTimeout block has expired. */
public class TimeoutCancellationException : CancellationException {
    internal constructor(message: String) : super(message)
    internal constructor(message: String, coroutine: Job?) : super(message)
}
