class Chan {
    fun cancel(cause: Throwable?): String = if (cause == null) "member-null" else "member-cause"
}

fun Chan.cancel(): String = "extension"

fun Chan.read2(): String {
    val first = cancel(null)
    try {
        throw IllegalStateException("cause")
    } catch (cause: Throwable) {
        return first + ":" + cancel(cause)
    }
}

class Job
fun Job.getCancellationException(): String = "job-extension"
interface ChannelJob { val job: Job }
class WrappedJob(override val job: Job) : ChannelJob
fun ChannelJob.getCancellationException(): String = job.getCancellationException()

fun main() {
    val channel = Chan()
    println(channel.read2())
    println(channel.cancel())
    println(channel.cancel(null))
    val wrapped: ChannelJob = WrappedJob(Job())
    println(wrapped.getCancellationException())
}
