package kotlinx.coroutines.future

import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionStage
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job

public fun Job.asCompletableFuture(): CompletableFuture<Unit> {
    val cf = CompletableFuture<Unit>()
    cf.complete(Unit)
    return cf
}

@Suppress("UNCHECKED_CAST")
public fun <T> Deferred.asCompletableFuture(): CompletableFuture<T> {
    val cf = CompletableFuture<T>()
    return cf
}

public fun <T> CompletionStage<T>.asDeferred(): Deferred {
    throw UnsupportedOperationException("CompletionStage.asDeferred is a nominal stub")
}

public suspend fun <T> CompletionStage<T>.await(): T {
    return toCompletableFuture().get()
}

public fun <T> future(
    context: CoroutineContext = EmptyCoroutineContext,
    block: suspend () -> T
): CompletableFuture<T> {
    val cf = CompletableFuture<T>()
    return cf
}
