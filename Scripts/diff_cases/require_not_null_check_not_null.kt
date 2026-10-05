fun main() {
    val s: String? = "hello"
    println(requireNotNull(s).length)

    val n: Int? = 42
    println(checkNotNull(n))

    val nullStr: String? = null
    try {
        requireNotNull(nullStr)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        requireNotNull(nullStr) { "custom require" }
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }

    try {
        checkNotNull(nullStr)
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    try {
        checkNotNull(nullStr) { "custom check" }
    } catch (e: IllegalStateException) {
        println(e.message)
    }

    // KUU-1091: `returns() implies (value != null)` narrows the argument itself.
    val e: String? = "v"
    requireNotNull(e)
    println(e.length)

    val g: String? = "y"
    checkNotNull(g)
    println(g.length)
}
