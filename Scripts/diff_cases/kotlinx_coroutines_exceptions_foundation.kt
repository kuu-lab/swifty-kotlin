import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.InternalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.ExperimentalForInheritanceCoroutinesApi
import kotlinx.coroutines.ObsoleteCoroutinesApi
import kotlinx.coroutines.TimeoutCancellationException

// A timeout is a cancellation, even though its constructors are internal.
fun asCancellation(timeout: TimeoutCancellationException): CancellationException = timeout

@OptIn(
    ExperimentalCoroutinesApi::class,
    DelicateCoroutinesApi::class,
    InternalCoroutinesApi::class,
    FlowPreview::class,
    ExperimentalForInheritanceCoroutinesApi::class,
    ObsoleteCoroutinesApi::class
)
fun main() {
    val exception: CancellationException = CancellationException("cancelled")
    println(exception is kotlin.coroutines.cancellation.CancellationException)
    println(exception.message)
    try {
        throw exception
    } catch (caught: CancellationException) {
        println(caught.message)
    }
}
