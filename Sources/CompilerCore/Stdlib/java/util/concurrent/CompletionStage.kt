package java.util.concurrent

public interface CompletionStage<T> {
    public fun toCompletableFuture(): CompletableFuture<T>

    public fun <U> thenApply(action: (T) -> U): CompletionStage<U>

    public fun <U> thenCompose(action: (T) -> CompletionStage<U>): CompletionStage<U>

    public fun whenComplete(action: (T?, Throwable?) -> Unit): CompletionStage<T>
}
