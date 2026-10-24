package kotlinx.coroutines.future

import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionStage
import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.InternalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.invokeOnCompletion
import kotlinx.coroutines.suspendCancellableCoroutine

public fun Job.asCompletableFuture(): CompletableFuture<Unit> {
    val cf = CompletableFuture<Unit>()
    invokeOnCompletion { cause ->
        when (cause) {
            null -> cf.complete(Unit)
            is CancellationException -> cf.cancel(false)
            else -> cf.completeExceptionally(cause)
        }
    }
    cf.whenComplete { _, _ ->
        if (cf.isCancelled) cancel()
    }
    return cf
}

public fun <T> Deferred<T>.asCompletableFuture(): CompletableFuture<T> {
    val cf = CompletableFuture<T>()
    invokeOnCompletion { cause ->
        when (cause) {
            null -> cf.complete(getCompleted())
            is CancellationException -> cf.cancel(false)
            else -> cf.completeExceptionally(cause)
        }
    }
    cf.whenComplete { _, _ ->
        if (cf.isCancelled) cancel()
    }
    return cf
}

public fun <T> CompletionStage<T>.asDeferred(): Deferred<T> {
    val future = toCompletableFuture()
    val deferred = CompletableDeferred<T>()
    future.whenComplete { value, failure ->
        when (failure) {
            null -> deferred.complete(value as T)
            is CancellationException -> deferred.cancel(failure)
            else -> deferred.completeExceptionally(failure)
        }
    }
    deferred.invokeOnCompletion { cause ->
        if (cause is CancellationException) future.cancel(false)
    }
    return deferred
}

@OptIn(InternalCoroutinesApi::class)
public suspend fun <T> CompletionStage<T>.await(): T {
    val future = toCompletableFuture()
    return suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { future.cancel(false) }
        future.whenComplete { value, failure ->
            if (failure == null) {
                val token = continuation.tryResume(value as T)
                if (token != null) continuation.completeResume(token)
            } else {
                val token = continuation.tryResumeWithException(failure)
                if (token != null) continuation.completeResume(token)
            }
        }
    }
}

public fun <T> future(
    context: CoroutineContext = EmptyCoroutineContext,
    block: suspend () -> T
): CompletableFuture<T> {
    val deferred = CoroutineScope(context).async { block() }
    return deferred.asCompletableFuture()
}
