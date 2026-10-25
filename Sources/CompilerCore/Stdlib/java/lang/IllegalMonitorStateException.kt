package java.lang

// KUU-3059: thrown by java.util.concurrent.locks when the current thread
// does not hold the lock it tries to release or signal on.
public open class IllegalMonitorStateException : RuntimeException {
    public constructor() : super()
    public constructor(message: String?) : super(message)
}
