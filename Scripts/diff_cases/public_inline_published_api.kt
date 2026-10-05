@PublishedApi
internal inline fun hidden(): Int {
    try { return 55 } finally { println("hidden-finally") }
}

inline fun exposed(): Int = hidden()

@PublishedApi
internal fun helper(): Int = 7

inline fun exposedHelper(): Int = helper()

private inline fun privateHelper(): Int = 9
internal inline fun internalCaller(): Int = privateHelper()

fun main() {
    println(exposed())
    println(exposedHelper())
    println(internalCaller())
}
