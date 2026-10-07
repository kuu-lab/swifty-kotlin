package java.util.concurrent

public interface CompletionStage<T> {
    public fun toCompletableFuture(): CompletableFuture<T>
}
