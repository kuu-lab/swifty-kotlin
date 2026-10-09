import kotlin.coroutines.cancellation.CancellationException

// KUU-1597 Sema owner: pin CancellationException constructor overloads and supertypes; message/cause values stay in Scripts/diff_cases/stdlib_kotlin_coroutines_cancellation_n_n.kt.
fun main() {
    val noArg: CancellationException = CancellationException()
    val message: CancellationException = CancellationException("message")
    val cause: CancellationException = CancellationException(IllegalArgumentException("cause"))
    val messageAndCause: CancellationException = CancellationException(
        "both",
        IllegalArgumentException("root"),
    )
    val nullableMessage: String? = CancellationException(null as Throwable?).message
    val nullableCause: Throwable? = CancellationException(null, null).cause
    val isIllegalState: Boolean = messageAndCause is IllegalStateException
    val isException: Boolean = messageAndCause is Exception
    val isThrowable: Boolean = messageAndCause is Throwable
}
