package java.util.concurrent

import java.lang.Runnable

public interface CompletionStage<T> {
    public fun toCompletableFuture(): CompletableFuture<T>
    public fun <U> thenApply(action: (T) -> U): CompletionStage<U>
    public fun <U> thenApplyAsync(action: (T) -> U): CompletionStage<U>
    public fun <U> thenApplyAsync(action: (T) -> U, executor: Executor?): CompletionStage<U>
    public fun <U> thenCompose(action: (T) -> CompletionStage<U>): CompletionStage<U>
    public fun <U> thenComposeAsync(action: (T) -> CompletionStage<U>): CompletionStage<U>
    public fun <U> thenComposeAsync(action: (T) -> CompletionStage<U>, executor: Executor?): CompletionStage<U>
    public fun whenComplete(action: (T?, Throwable?) -> Unit): CompletionStage<T>
    public fun whenCompleteAsync(action: (T?, Throwable?) -> Unit): CompletionStage<T>
    public fun whenCompleteAsync(action: (T?, Throwable?) -> Unit, executor: Executor?): CompletionStage<T>
    public fun <U> handle(action: (T?, Throwable?) -> U): CompletionStage<U>
    public fun <U> handleAsync(action: (T?, Throwable?) -> U): CompletionStage<U>
    public fun <U> handleAsync(action: (T?, Throwable?) -> U, executor: Executor?): CompletionStage<U>
    public fun thenAccept(action: (T) -> Unit): CompletionStage<Unit>
    public fun thenAcceptAsync(action: (T) -> Unit): CompletionStage<Unit>
    public fun thenAcceptAsync(action: (T) -> Unit, executor: Executor?): CompletionStage<Unit>
    public fun thenRun(action: Runnable): CompletionStage<Unit>
    public fun thenRunAsync(action: Runnable): CompletionStage<Unit>
    public fun thenRunAsync(action: Runnable, executor: Executor?): CompletionStage<Unit>
    public fun exceptionally(action: (Throwable) -> T): CompletionStage<T>
    public fun exceptionallyAsync(action: (Throwable) -> T): CompletionStage<T>
    public fun exceptionallyAsync(action: (Throwable) -> T, executor: Executor?): CompletionStage<T>
}
