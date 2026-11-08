package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext

// Upstream `runInterruptible` is a JVM-only API that runs the blocking
// [block] under [withContext] and interrupts the worker thread on caller
// cancellation. The native runtime has no thread-interrupt primitive, so the
// context-switching contract is preserved while interruption degrades to
// ordinary coroutine cancellation. The context parameter is exposed through
// an overload pair instead of a default value because the precompiled
// stdlib's default-argument stub does not forward suspend arguments
// correctly.
public suspend fun <T> runInterruptible(block: () -> T): T =
    runInterruptible(EmptyCoroutineContext, block)

public suspend fun <T> runInterruptible(
    context: CoroutineContext,
    block: () -> T
): T = withContext(context) { block() }
