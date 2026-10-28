package java.util.concurrent

// KUU-3059: the java.util.concurrent exception family. CancellationException
// stays source-backed by kotlin.coroutines.cancellation, avoiding a dependency
// on the optional kotlinx.coroutines package.

public open class ExecutionException : Exception {
    public constructor() : super()
    public constructor(message: String?) : super(message)
    public constructor(message: String?, cause: Throwable?) : super(message, cause)
    public constructor(cause: Throwable?) : super(cause)
}

public open class TimeoutException : Exception {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class BrokenBarrierException : Exception {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}

public open class RejectedExecutionException : RuntimeException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
    public constructor(message: String?, cause: Throwable?) : super(message, cause)
    public constructor(cause: Throwable?) : super(cause)
}
