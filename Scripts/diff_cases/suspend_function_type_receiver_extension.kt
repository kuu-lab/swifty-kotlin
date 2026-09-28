// KUU-915: a suspend function type may be the receiver of an extension.
fun <R> (suspend () -> R).fireAndForget(): String {
    this.hashCode()
    return "ok"
}

fun main() {
    val work: suspend () -> Int = { 42 }
    println(work.fireAndForget())
}
