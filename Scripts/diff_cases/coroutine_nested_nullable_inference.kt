// KUU-1132: infer nullable results without an outer expected type.
import kotlinx.coroutines.*

suspend fun <T> wrap(block: suspend () -> T): T? =
    withTimeoutOrNull(5000L) { block() }

fun main() = runBlocking {
    val timed = withTimeout(5000) { withTimeoutOrNull(5000L) { "timed" } }
    val nullableTimed = withTimeoutOrNull(5000) { withTimeoutOrNull(5000L) { "nullable" } }
    val scoped = coroutineScope { withTimeoutOrNull(5000L) { "scoped" } }
    val supervised = supervisorScope { withTimeoutOrNull(5000L) { "supervised" } }
    val switched = withContext(Dispatchers.Default) { withTimeoutOrNull(5000L) { "switched" } }
    val explicit: String? = withTimeout(5000) { withTimeoutOrNull(5000L) { "explicit" } }
    val nullOnly = withTimeout(5000) { withTimeoutOrNull(5000L) { null } }
    val nullableBody = withTimeout(5000) { withTimeoutOrNull(5000L) { null as String? } }
    val wrapped = wrap { "wrapped" }
    val wrappedNull = wrap { null as String? }
    val expired = withTimeout(5000) { withTimeoutOrNull(0L) { "unreachable" } }
    println(timed?.length)
    println(nullableTimed?.length)
    println(scoped?.length)
    println(supervised?.length)
    println(switched?.length)
    println(explicit?.length)
    println(nullOnly)
    println(nullableBody?.length)
    println(wrapped?.length)
    println(wrappedNull?.length)
    println(expired?.length)
}
