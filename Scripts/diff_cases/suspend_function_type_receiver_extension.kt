// KUU-915: a suspend function type may be the receiver of an extension.
fun <R> (suspend () -> R).fireAndForget(): String {
    this.hashCode()
    return "ok"
}

suspend fun flushAndClose(): Int = 42

fun main() {
    val work: suspend () -> Int = { 42 }
    println(work.fireAndForget())
    // KUU-915's ktor-io call site passes a callable reference directly.
    println(::flushAndClose.fireAndForget())
}
