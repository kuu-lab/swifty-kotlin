// KUU-754: A null-only argument must still infer requireNotNull's T.
fun requireWithoutMessage() {
    try {
        requireNotNull(null)
    } catch (x: IllegalArgumentException) {
        println("req")
    }
}

fun requireWithMessage() {
    try {
        requireNotNull(null) { "lazy-req" }
    } catch (x: IllegalArgumentException) {
        println(x.message)
    }
}

fun checkWithoutMessage() {
    try {
        checkNotNull(null)
    } catch (x: IllegalStateException) {
        println("check")
    }
}

fun checkWithMessage() {
    try {
        checkNotNull(null) { "lazy-check" }
    } catch (x: IllegalStateException) {
        println(x.message)
    }
}

fun main() {
    requireWithoutMessage()
    requireWithMessage()
    checkWithoutMessage()
    checkWithMessage()
}
