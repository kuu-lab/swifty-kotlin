package java.util.concurrent

public open class CompletableFuture<T> : Future<T>, CompletionStage<T> {
    private var result: T? = null
    private var exception: Throwable? = null
    private var isCompleted: Boolean = false
    private var isCancelledFlag: Boolean = false

    public constructor()

    public open fun complete(value: T): Boolean {
        if (isCompleted) return false
        result = value
        isCompleted = true
        return true
    }

    public open fun completeExceptionally(ex: Throwable): Boolean {
        if (isCompleted) return false
        exception = ex
        isCompleted = true
        return true
    }

    public override fun cancel(mayInterruptIfRunning: Boolean): Boolean {
        if (isCompleted) return false
        isCancelledFlag = true
        isCompleted = true
        return true
    }

    public override fun isCancelled(): Boolean = isCancelledFlag
    public override fun isDone(): Boolean = isCompleted

    @Suppress("UNCHECKED_CAST")
    public override fun get(): T {
        val ex = exception
        if (ex != null) {
            throw ex
        }
        return result as T
    }

    public open fun join(): T = get()

    public override fun toCompletableFuture(): CompletableFuture<T> = this

    public companion object {
        public fun <U> completedFuture(value: U): CompletableFuture<U> {
            val cf = CompletableFuture<U>()
            cf.complete(value)
            return cf
        }

        public fun <U> failedFuture(ex: Throwable): CompletableFuture<U> {
            val cf = CompletableFuture<U>()
            cf.completeExceptionally(ex)
            return cf
        }
    }
}
